import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct SuningTimeConfiguration {
    var endpoint = URL(string: "https://f.m.suning.com/api/ct.do")!
    var validSamples = 8
    var maxAttempts = 12
    var timeoutMs = 1500
    var intervalMs = 0
    var maxRttMs = 300.0
    var maxSpreadMs = 50.0
    var maximumUncertaintyMs = 250.0
    var maximumAgeMs = 120_000.0
}
struct HTTPTimeSample {
    let sent: Double; let received: Double; let serverUTC: Double
    var rtt: Double { received - sent }
    var offset: Double { serverUTC - (sent + (received-sent)/2) }
}
struct HTTPTimeRateLimit: LocalizedError {
    let delayMs: Double
    var errorDescription: String? { "HTTP 时间源限流或暂不可用，约 \(Int(ceil(delayMs/1000))) 秒后可重试" }
}
enum SuningTimeProtocol {
    static func retryDelayMs(status: Int, retryAfter: String?, now: Date = Date()) -> Double? {
        guard status == 429 || status == 503 else { return nil }
        if let retryAfter {
            if let seconds = Double(retryAfter), seconds.isFinite, seconds >= 0 {
                return max(1000, min(seconds, 31_536_000) * 1000)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from:retryAfter) { return max(1000,date.timeIntervalSince(now)*1000) }
        }
        return 60_000
    }
    private struct Response: Decodable { let api: String; let code: String; let currentTime: Int64 }
    static func timestamp(_ data: Data, status: Int, age: String? = nil) throws -> Double {
        guard status == 200, data.count <= 16_384,
              age == nil || (Double(age!) == 0),
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.api == "time", response.code == "1",
              (946_684_800_000...4_102_444_800_000).contains(response.currentTime) else {
            throw ClientError.message("苏宁时间响应无效或被缓存")
        }
        return Double(response.currentTime)
    }
    static func select(_ samples: [HTTPTimeSample], config: SuningTimeConfiguration) throws -> ClockMapping {
        guard samples.count >= config.validSamples, samples.allSatisfy({ $0.rtt.isFinite && $0.rtt >= 0 && $0.rtt <= config.maxRttMs && $0.offset.isFinite }) else { throw ClientError.message("HTTP 有效样本不足") }
        let offsets = samples.map(\.offset)
        guard offsets.max()! - offsets.min()! <= config.maxSpreadMs else { throw ClientError.message("HTTP 时间偏移不稳定，请重试") }
        let selected = Array(samples.sorted { $0.rtt < $1.rtt }.prefix(max(3, config.validSamples/2)))
        let center = selected.map(\.offset).sorted()[selected.count/2]
        let spread = selected.map { abs($0.offset-center) }.max()!
        // Engineering estimate only: server accuracy, timestamp semantics and path asymmetry
        // are unverified. RTT/2 is one budget component, never measured absolute accuracy.
        let span = max(0, samples.map(\.received).max()! - samples.map(\.sent).min()!)
        let estimate = selected.map(\.rtt).max()!/2 + spread + 25 + span * 50 / 1_000_000
        guard estimate <= config.maximumUncertaintyMs else { throw ClientError.message("HTTP 校时超出估计不确定度预算") }
        let local = MonotonicClock.now()
        var mapping = ClockMapping(offset:center,uncertaintyMs:estimate,averageRttMs:selected.map(\.rtt).reduce(0,+)/Double(selected.count),sampledAt:local/1000)
        mapping.server = "f.m.suning.com"; mapping.validSamples = samples.count
        mapping.maximumAgeMs = config.maximumAgeMs; mapping.maximumUncertaintyMs = config.maximumUncertaintyMs
        mapping.referenceMono = MonotonicClock.nanosAt(local); mapping.referenceUTC = local + center
        return mapping
    }
}

@MainActor final class SuningTimeClient {
    static let shared = SuningTimeClient()
    var configuration = SuningTimeConfiguration()
    private(set) var latest: ClockMapping?
    private var stale = false
    private var generation = 0
    private var blockedUntil = -Double.infinity
    private var task: Task<ClockMapping, Error>?
    private var observers: [UUID: (Int, String) -> Void] = [:]
    private var state = (0, "准备 HTTP 校时")
    var exchange: (() async throws -> HTTPTimeSample)?
    var pause: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds:$0) }
    private let session: URLSession
    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 1.5; configuration.timeoutIntervalForResource = 1.5
        session = URLSession(configuration:configuration)
    }
    func invalidate() { stale = true; generation += 1 }
    private func report(_ count: Int, _ detail: String) {
        state = (count, detail)
        for observer in Array(observers.values) { observer(count, detail) }
    }
    func synchronize(detail: @escaping (String) -> Void = { _ in }, progress: @escaping (Int) -> Void = { _ in }) async throws -> ClockMapping {
        let id = UUID(); observers[id] = { progress($0); detail($1) }
        defer { observers.removeValue(forKey:id) }
        if let task { progress(state.0); detail(state.1); return try await task.value }
        if !stale, let latest, latest.fresh { progress(latest.validSamples); detail("苏宁 HTTP · 使用有效校时结果"); return latest }
        let startedGeneration = generation
        let task = Task { try await collect() }; self.task = task
        defer { self.task = nil }
        do {
            let value = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard startedGeneration == generation else { throw ClientError.message("网络环境已变化，请重新校时") }
            latest = value; stale = false; return value
        } catch { report(state.0, "苏宁 HTTP 校时失败：\(error.localizedDescription)"); throw error }
    }
    private func collect() async throws -> ClockMapping {
        let config = configuration
        guard MonotonicClock.now() >= blockedUntil else { throw HTTPTimeRateLimit(delayMs:blockedUntil-MonotonicClock.now()) }
        guard config.validSamples >= 3, config.maxAttempts >= config.validSamples, config.intervalMs >= 0, config.timeoutMs > 0, config.maxRttMs > 0, config.maxSpreadMs >= 0, config.maximumAgeMs > 0, config.maximumUncertaintyMs > 0, config.endpoint.scheme == "https" else { throw ClientError.message("HTTP 校时配置无效") }
        var samples: [HTTPTimeSample] = []; var lastTimestamp: Double?; var lastError = ""
        for attempt in 0..<config.maxAttempts {
            try Task.checkCancellation()
            if attempt > 0 && config.intervalMs > 0 { try await pause(UInt64(config.intervalMs)*1_000_000) }
            report(min(samples.count,config.validSamples), "苏宁 HTTP · 第 \(attempt+1) 次请求")
            do {
                let sample: HTTPTimeSample
                if let exchange { sample = try await exchange() } else { sample = try await request(config) }
                guard sample.rtt >= 0, sample.rtt <= config.maxRttMs, sample.offset.isFinite,
                      lastTimestamp == nil || sample.serverUTC > lastTimestamp! else { throw ClientError.message("延迟超标或服务器时间未推进") }
                lastTimestamp = sample.serverUTC; samples.append(sample)
                report(min(samples.count,config.validSamples), "苏宁 HTTP · RTT \(String(format:"%.1f",sample.rtt)) ms · Offset \(String(format:"%.1f",sample.offset)) ms")
                if samples.count >= config.validSamples {
                    let mapping = try SuningTimeProtocol.select(Array(samples.suffix(config.validSamples)),config:config)
                    report(config.validSamples, "苏宁 HTTP · 校时完成，实际精度未经验证")
                    return mapping
                }
            } catch is CancellationError { throw CancellationError() }
            catch let limited as HTTPTimeRateLimit {
                blockedUntil = MonotonicClock.now() + limited.delayMs
                report(min(samples.count,config.validSamples), limited.localizedDescription)
                throw limited
            }
            catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error.localizedDescription
                report(min(samples.count,config.validSamples), "苏宁 HTTP · \(lastError)")
            }
        }
        throw ClientError.message("苏宁 HTTP 有效样本或质量不足（\(min(samples.count,config.validSamples))/\(config.validSamples)）：\(lastError)")
    }
    private func request(_ config: SuningTimeConfiguration) async throws -> HTTPTimeSample {
        var url = URLComponents(url:config.endpoint,resolvingAgainstBaseURL:false)!
        url.queryItems = (url.queryItems ?? []) + [URLQueryItem(name:"_runtick",value:UUID().uuidString)]
        var request = URLRequest(url:url.url!,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:Double(config.timeoutMs)/1000)
        request.setValue("no-cache, no-store",forHTTPHeaderField:"Cache-Control")
        request.setValue("no-cache",forHTTPHeaderField:"Pragma")
        let sent = MonotonicClock.now()
        let (data, response) = try await session.data(for:request)
        let received = MonotonicClock.now()
        guard let response = response as? HTTPURLResponse, response.url?.host == config.endpoint.host, response.url?.scheme == "https" else { throw ClientError.message("HTTP 时间源重定向无效") }
        if let delay = SuningTimeProtocol.retryDelayMs(status:response.statusCode,retryAfter:response.value(forHTTPHeaderField:"Retry-After")) { throw HTTPTimeRateLimit(delayMs:delay) }
        let timestamp = try SuningTimeProtocol.timestamp(data,status:response.statusCode,age:response.value(forHTTPHeaderField:"Age"))
        return HTTPTimeSample(sent:sent,received:received,serverUTC:timestamp)
    }
}

// NTP remains available as an explicit option; no automatic mixed-source fallback.
@MainActor enum AppTimeSync {
    enum Source { case suningHTTP, ntp }
    static var source: Source = .suningHTTP
    static var latest: ClockMapping? { source == .suningHTTP ? SuningTimeClient.shared.latest : NtpClient.shared.latest }
    static var target: Int { source == .suningHTTP ? SuningTimeClient.shared.configuration.validSamples : NtpClient.shared.configuration.validSamples }
    static func invalidate() { SuningTimeClient.shared.invalidate() }
    static func synchronize(detail: @escaping (String)->Void = { _ in }, progress: @escaping (Int)->Void = { _ in }) async throws -> ClockMapping {
        if source == .suningHTTP { return try await SuningTimeClient.shared.synchronize(detail:detail,progress:progress) }
        return try await NtpClient.shared.synchronize(detail:detail,progress:progress)
    }
}
