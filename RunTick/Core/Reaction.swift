import Foundation

struct ReactionResult: Codable {
    let reactionMs: Double?
    let reactionStatus: String
    var text: String { Self.text(reactionMs, reactionStatus) }
    static func text(_ ms: Double?, _ status: String?) -> String {
        if status == "detected", let ms { return String(format: "起跑反应 %.1f ms", ms) }
        if status == "false_start", let ms { return String(format: "抢跑 · %.1f ms（＜100 ms）", ms) }
        return ["disabled": "未启用反应时检测", "timeout": "未检测到移动", "unavailable": "传感器不可用或未授权", "unstable": "放置不稳定", "cancelled": "检测已中断"][status ?? ""] ?? "未记录反应时"
    }
}
struct MotionGate {
    private(set) var ready = false
    private(set) var movedAt: Double?
    private var quiet: Double?
    private var candidate: Double?
    mutating func sample(at: Double, acceleration: Double, rotation: Double) {
        guard at.isFinite, acceleration.isFinite, rotation.isFinite else { return }
        if !ready {
            if acceleration < 0.18 && rotation < 0.12 {
                if quiet == nil { quiet = at }; ready = at - quiet! >= 500
            } else { quiet = nil }
            return
        }
        guard movedAt == nil else { return }
        if (acceleration > 0.45 && rotation > 0.2) || acceleration > 1.5 {
            if candidate == nil { candidate = at }
            if at - candidate! >= 25 { movedAt = candidate }
        } else { candidate = nil }
    }
}
struct SoloRecord: Codable, Identifiable {
    let id: String; let createdAt: Double
    let reactionMs: Double?; let reactionStatus: String
}
struct SoloRecords: Decodable { let records: [SoloRecord]; let hasMore: Bool }
