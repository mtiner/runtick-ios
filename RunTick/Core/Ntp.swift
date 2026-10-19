import Foundation

struct NtpConfiguration {
    var servers = ["ntp.tencent.com", "ntp.aliyun.com"]
    var timeoutMs = 1500
    var validSamples = 8
    var maxAttempts = 12
    var intervalMs = 16_000
    var maxRttMs = 100.0
    var maxSpreadMs = 10.0
    var consecutiveFailureLimit = 1
    var driftPpm = 50.0
    var maximumAgeMs = 120_000.0
    var maximumUncertaintyMs = 25.0
}
enum NtpPacket {
    static func timestamp(_ bytes: [UInt8], _ at: Int, pivotMs: Double) -> Double {
        func word(_ index: Int) -> Double { Double(bytes[index..<index+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }) }
        let seconds = word(at), pivot = pivotMs / 1000 + 2_208_988_800
        let era = ((pivot - seconds) / 4_294_967_296).rounded()
        return (seconds + era * 4_294_967_296 - 2_208_988_800 + word(at+4) / 4_294_967_296) * 1000
    }
    static func write(_ bytes: inout [UInt8], _ at: Int, utcMs: Double) {
        let seconds = utcMs / 1000 + 2_208_988_800
        let whole = UInt32(truncatingIfNeeded: UInt64(floor(seconds)))
        let fraction = UInt32((seconds - floor(seconds)) * 4_294_967_296)
        for j in 0..<4 { bytes[at+j] = UInt8(truncatingIfNeeded: whole >> (24-j*8)); bytes[at+4+j] = UInt8(truncatingIfNeeded: fraction >> (24-j*8)) }
    }
    struct Kiss: Error { let code: String; let poll: Int }
    static func parse(_ bytes: [UInt8], request: [UInt8], t1: Double, t4: Double) throws -> ClockSample {
        guard bytes.count >= 48 else { throw ClientError.message("NTP 报文过短") }
        let header = bytes[0]
        guard (3...4).contains((header >> 3) & 7), header & 7 == 4,
              Array(bytes[24..<32]) == Array(request[40..<48]) else { throw ClientError.message("NTP 版本、模式或请求标识无效") }
        if bytes[1] == 0 { throw Kiss(code: String(bytes: bytes[12..<16], encoding: .ascii) ?? "????", poll: Int(Int8(bitPattern: bytes[2]))) }
        guard header >> 6 != 3, (1...15).contains(bytes[1]), bytes[32..<40].contains(where: { $0 != 0 }), bytes[40..<48].contains(where: { $0 != 0 }) else { throw ClientError.message("NTP 服务器未同步") }
        let t2 = timestamp(bytes,32,pivotMs:t1), t3 = timestamp(bytes,40,pivotMs:t1)
        guard t3 >= t2, t3-t2 <= 1500, t4 >= t1, t4-t1-(t3-t2) >= -0.001 else { throw ClientError.message("NTP 时间顺序无效") }
        func word(_ at: Int) -> UInt32 { bytes[at..<at+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
        let rootDelay = Double(Int32(bitPattern: word(4))) / 65536 * 1000
        let dispersion = Double(word(8)) / 65536 * 1000
        guard rootDelay >= 0, rootDelay <= 1000, dispersion <= 1000 else { throw ClientError.message("NTP 根距离无效") }
        return ClockSample(sent:t1, received:t4, serverReceived:t2, serverSent:t3, rootDistanceMs:rootDelay/2+dispersion)
    }
}
#if canImport(Network)
import Network

// Serial queue owns the continuation and connection, including cancellation and timeout.
private final class NtpExchange: @unchecked Sendable {
    let queue = DispatchQueue(label: "cc.runtick.ntp")
    var connection: NWConnection?
    var continuation: CheckedContinuation<ClockSample, Error>?
    var cancelled = false
    func finish(_ result: Result<ClockSample, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        let active = connection; connection = nil; active?.stateUpdateHandler = nil; active?.cancel()
        continuation.resume(with: result)
    }
    func cancel() { queue.async { self.cancelled = true; self.finish(.failure(CancellationError())) } }
    func run(server: String, timeoutMs: Int) async throws -> ClockSample {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    if self.cancelled { self.finish(.failure(CancellationError())); return }
                    let connection = NWConnection(host: NWEndpoint.Host(server), port: 123, using: .udp)
                    self.connection = connection
                    var sent = false
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            guard !sent else { return }; sent = true
                            var request = [UInt8](repeating:0,count:48); request[0] = 0x23
                            let t1 = MonotonicClock.now(); NtpPacket.write(&request,40,utcMs:t1)
                            let packet = request
                            connection.send(content: Data(packet), completion: .contentProcessed { error in
                                if let error { self.finish(.failure(error)) }
                            })
                            connection.receiveMessage { data, _, _, error in
                                let t4 = MonotonicClock.now()
                                if let error { self.finish(.failure(error)); return }
                                do { self.finish(.success(try NtpPacket.parse(Array(data ?? Data()),request:packet,t1:t1,t4:t4))) }
                                catch { self.finish(.failure(error)) }
                            }
                        case .failed(let error): self.finish(.failure(error))
                        default: break
                        }
                    }
                    self.queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { self.finish(.failure(ClientError.message("NTP 请求超时"))) }
                    connection.start(queue:self.queue)
                }
            }
        }, onCancel: { self.cancel() })
    }
}
#endif
@MainActor final class NtpClient {
    static let shared = NtpClient()
    private(set) var latest: ClockMapping?
    private var inFlight: Task<ClockMapping, Error>?
    private var observers: [UUID: (Int, String) -> Void] = [:]
    private var currentProgress = 0
    private var currentDetail = "准备校时"
    private func report(_ count: Int, _ detail: String) {
        currentProgress = count; currentDetail = detail
        for observer in Array(observers.values) { observer(count, detail) }
    }
    func synchronize(detail: @escaping (String) -> Void = { _ in }, progress: @escaping (Int) -> Void) async throws -> ClockMapping {
        let id = UUID()
        observers[id] = { count, message in progress(count); detail(message) }
        defer { observers.removeValue(forKey: id) }
        if let inFlight {
            progress(currentProgress); detail(currentDetail)
            return try await inFlight.value
        }
        report(0, "准备校时")
        let task = Task { try await collect() }
        inFlight = task
        defer { inFlight = nil }
        let value = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        latest = value
        return value
    }
    var exchange: ((String, Int) async throws -> ClockSample)?
    var pause: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds:$0) }
    var configuration = NtpConfiguration()
    private var blockedUntil: [String: Double] = [:]
    private var denied = Set<String>()
    private var lastRequest = -Double.infinity
    private func collect() async throws -> ClockMapping {
        let config = configuration
        guard config.validSamples >= 3, config.maxAttempts >= config.validSamples, config.intervalMs >= 16000, (1...60000).contains(config.timeoutMs), config.consecutiveFailureLimit >= 1, !config.servers.isEmpty, config.driftPpm.isFinite, config.driftPpm >= 0, config.maximumAgeMs > 0, config.maximumUncertaintyMs > 0 else { throw ClientError.message("NTP 配置无效") }
        var errors: [String] = []
        for server in config.servers {
            if denied.contains(server) || MonotonicClock.now() < (blockedUntil[server] ?? 0) { continue }
            var samples: [ClockSample] = []
            var failures = 0
            for _ in 0..<config.maxAttempts {
                try Task.checkCancellation()
                let wait = Double(config.intervalMs) - (MonotonicClock.now() - lastRequest)
                if wait > 0 {
                    report(samples.count, "\(server) · 等待下次采样（约 \(Int(ceil(wait/1000))) 秒）· \(currentDetail)")
                    try await pause(UInt64(wait * 1_000_000))
                }
                report(samples.count, "\(server) · 请求中（超时 \(config.timeoutMs) ms）")
                lastRequest = MonotonicClock.now()
                do {
                    let sample: ClockSample
                    if let exchange { sample = try await exchange(server,config.timeoutMs) }
                    else {
                        #if canImport(Network)
                        sample = try await NtpExchange().run(server:server,timeoutMs:config.timeoutMs)
                        #else
                        throw ClientError.message("Native UDP requires Network.framework")
                        #endif
                    }
                    failures = 0
                    let rtt = sample.received-sample.sent-(sample.serverSent-sample.serverReceived)
                    let offset = ((sample.serverReceived-sample.sent)+(sample.serverSent-sample.received))/2
                    print("RunTick NTP \(server) RTT=\(rtt) offset=\(offset)")
                    if rtt <= config.maxRttMs {
                        samples.append(sample)
                        report(samples.count, "\(server) · 有效响应 · RTT \(String(format: "%.1f", rtt)) ms · Offset \(String(format: "%.1f", offset)) ms")
                    } else {
                        report(samples.count, "\(server) · 已响应但 RTT \(String(format: "%.1f", rtt)) ms 超出阈值，未计入有效样本")
                    }
                    if samples.count >= config.validSamples {
                        let offsets = samples.map { (($0.serverReceived-$0.sent)+($0.serverSent-$0.received))/2 }
                        guard (offsets.max()! - offsets.min()!) <= config.maxSpreadMs else { errors.append("\(server): Offset 不稳定"); report(samples.count, "\(server) · Offset 不稳定，切换服务器"); break }
                        var result = try NtpQuality.select(samples, driftPpm:config.driftPpm)
                        let local = MonotonicClock.now()
                        result.referenceMono = MonotonicClock.nanosAt(local); result.referenceUTC = local + result.offset
                        result.driftPpm = config.driftPpm; result.maximumAgeMs = config.maximumAgeMs; result.maximumUncertaintyMs = config.maximumUncertaintyMs
                        guard result.fresh else { throw ClientError.message("NTP 不确定度超出配置预算") }
                        result.server = server; result.validSamples = samples.count
                        report(samples.count, "\(server) · 校时完成")
                        return result
                    }
                } catch is CancellationError { throw CancellationError() }
                catch let kiss as NtpPacket.Kiss {
                    if kiss.code == "DENY" || kiss.code == "RSTR" { denied.insert(server) }
                    blockedUntil[server] = MonotonicClock.now() + max(60000, pow(2, Double(min(17,max(4,kiss.poll)))) * 1000)
                    errors.append("\(server): KoD \(kiss.code)"); report(samples.count, "\(server) · KoD \(kiss.code)，停止访问并退避"); break
                } catch { print("RunTick NTP \(server) error=\(error.localizedDescription)"); errors.append("\(server): \(error.localizedDescription)"); report(samples.count, "\(server) · \(error.localizedDescription)"); failures += 1; if failures >= config.consecutiveFailureLimit { break } }
            }
            errors.append("\(server): 有效样本 \(samples.count)/\(config.validSamples)，质量未通过")
        }
        let reason = "NTP 校时失败：" + errors.joined(separator: "; ")
        report(currentProgress, reason)
        throw ClientError.message(reason)
    }
}

enum NtpQuality {
    // Engineering estimate under bounded path asymmetry; not verified absolute accuracy.
    static func select(_ samples: [ClockSample], driftPpm: Double = 50) throws -> ClockMapping {
        let sorted = samples.sorted { ($0.received-$0.sent-($0.serverSent-$0.serverReceived)) < ($1.received-$1.sent-($1.serverSent-$1.serverReceived)) }
        let selected = Array(sorted.prefix(max(3,samples.count/2)))
        guard !selected.isEmpty else { throw ClientError.message("NTP 无有效样本") }
        let offsets = selected.map { (($0.serverReceived-$0.sent)+($0.serverSent-$0.received))/2 }.sorted()
        let offset = offsets[offsets.count/2]
        let rtt = selected.map { $0.received-$0.sent-($0.serverSent-$0.serverReceived) }.reduce(0,+)/Double(selected.count)
        let spread = offsets.map { abs($0-offset) }.max() ?? 0
        let span = max(0, (samples.map(\.received).max() ?? 0) - (samples.map(\.sent).min() ?? 0))
        let samplingDrift = span * driftPpm / 1_000_000
        let estimate = samplingDrift + rtt/2 + (selected.map(\.rootDistanceMs).max() ?? 0) + spread + 2
        guard estimate.isFinite, estimate <= 25 else { throw ClientError.message("NTP 校时质量不足") }
        return ClockMapping(offset:offset,uncertaintyMs:estimate,averageRttMs:rtt,sampledAt:MonotonicClock.now()/1000)
    }
}
