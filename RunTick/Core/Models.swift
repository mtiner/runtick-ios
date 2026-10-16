import Foundation

struct User: Codable, Identifiable { let id: Int; let loginId: String }
enum DeviceRole: String, Codable, CaseIterable { case start, finish
    var title: String { self == .start ? "起点" : "终点" }
}
struct Room: Codable { let code: String; let status: String? }
struct Member: Decodable, Identifiable {
    var id: String { loginId }; let loginId: String; let deviceRole: DeviceRole?; var online: Bool?
}
struct RoomDetail: Decodable { let room: Room; let ownerLoginId: String; let members: [Member] }
struct HubState: Decodable { let type: String; let members: [Member]?; let ready: Bool? }
struct SavedResult: Codable { let distance: Int; let isPb: Bool; let pbImprovementMs: Double? }
struct Race: Codable, Identifiable {
    let id: String; let status: String; let createdAt: Double
    let startAt: Double?; let finishAt: Double?; let elapsedMs: Double?; let uncertaintyMs: Double?
    let startUserId: Int; let finishUserId: Int; var savedResult: SavedResult?
    var starterSettings: [StageDelay]? = nil
    var reactionMs: Double? = nil; var reactionStatus: String? = nil
    var active: Bool { status == "ready" || status == "running" }
    func accepts(_ newer: Race) -> Bool {
        guard newer.createdAt >= createdAt else { return false }
        guard newer.id == id else { return true }
        return !(!active && newer.active) && !(savedResult != nil && newer.savedResult == nil)
            && !(reactionStatus != nil && newer.reactionStatus == nil)
            && !(startAt != nil && newer.startAt == nil) && !(finishAt != nil && newer.finishAt == nil)
    }
}
struct TimingEvent: Codable { let kind: DeviceRole; let at: Double; let uncertaintyMs: Double }
struct PendingEvent: Codable { let code: String; let raceId: String; let userId: Int; let event: TimingEvent }
struct HistoryRecord: Codable, Identifiable {
    var id: String { raceId }; let raceId: String; let athleteId: Int; let recorderId: Int
    let distance: Int; let elapsedMs: Double; let performedAt: Double; let savedAt: Double
    let isPb: Bool; let pbImprovementMs: Double?
    var reactionMs: Double? = nil; var reactionStatus: String? = nil
}
struct TrendPoint: Decodable, Identifiable { var id: String { raceId }; let raceId: String; let elapsedMs: Double; let performedAt: Double }
struct HistoryData: Decodable { let trend: [TrendPoint]; let athletes: [User]; let athleteId: Int; let distances: [Int]; let records: [HistoryRecord]; let hasMore: Bool }
struct UserResponse: Decodable { let user: User }
struct RoomResponse: Decodable { let room: Room }
struct RaceResponse: Decodable { let race: Race? }
struct SaveResponse: Decodable { let result: HistoryRecord; let created: Bool }
struct EmptyResponse: Decodable {}
struct ClockResponse: Decodable { let clientSentAt: Double; let receivedAt: Double; let sentAt: Double; let processingMs: Double }
struct StageDelay: Codable, Equatable {
    var random: Bool; var min: Double; var max: Double
    var enabled: Bool? = nil
    var reactionEnabled: Bool? = nil
    var valid: Bool { min.isFinite && max.isFinite && (0...30).contains(min) && (0...30).contains(max) && max >= min }
    func sample() -> Double { random ? Double.random(in: min...max) : min }
    var normalized: Self {
        let lower = min.isFinite ? Swift.min(30, Swift.max(0, min.rounded())) : 5
        var upper = max.isFinite ? Swift.min(30, Swift.max(lower, max.rounded())) : lower
        return Self(random: random, min: lower, max: upper, enabled: enabled, reactionEnabled: reactionEnabled)
    }
    mutating func setLower(_ value: Double) { min = Swift.min(max, Swift.max(0, value.rounded())) }
    mutating func setUpper(_ value: Double) { max = Swift.max(min, Swift.min(30, value.rounded())) }
    static let defaults = [StageDelay(random: false, min: 5, max: 5), StageDelay(random: false, min: 5, max: 5), StageDelay(random: true, min: 5, max: 10)]
}
struct ClockSample { let sent: Double; let received: Double; let serverReceived: Double; let serverSent: Double }
struct ClockMapping {
    let offset: Double; let uncertaintyMs: Double; let averageRttMs: Double; let sampledAt: Double
    var fresh: Bool { ProcessInfo.processInfo.systemUptime - sampledAt <= 120 }
    static func average(_ samples: [ClockSample]) throws -> Self {
        guard !samples.isEmpty else { throw ClientError.message("没有有效校时样本") }
        let rtts = samples.map { $0.received - $0.sent - ($0.serverSent - $0.serverReceived) }
        let offsets = samples.map { (($0.serverReceived - $0.sent) + ($0.serverSent - $0.received)) / 2 }
        let rtt = rtts.reduce(0,+) / Double(samples.count), offset = offsets.reduce(0,+) / Double(samples.count)
        let uncertainty = rtt / 2 + (offsets.map { abs($0 - offset) }.max() ?? 0) + 1
        guard offset.isFinite, uncertainty.isFinite, uncertainty <= 250, rtts.allSatisfy({ $0 >= 0 }) else { throw ClientError.message("网络延迟或波动过高，请重试校时") }
        return Self(offset: offset, uncertaintyMs: uncertainty, averageRttMs: rtt, sampledAt: ProcessInfo.processInfo.systemUptime)
    }
}
enum MonotonicClock {
    static let epoch = Date().timeIntervalSince1970 * 1000 - ProcessInfo.processInfo.systemUptime * 1000
    static func now() -> Double { epoch + ProcessInfo.processInfo.systemUptime * 1000 }
}

struct CurrentRoomResponse: Decodable { let room: Room? }
