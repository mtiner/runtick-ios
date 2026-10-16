import CoreMotion
import Foundation

@MainActor final class ReactionMotion {
    private let manager = CMMotionManager()
    private var gate = MotionGate()
    private var gunAt: Double?
    private var callback: ((ReactionResult) -> Void)?
    private var timeout: Task<Void, Never>?
    private var received = false
    private var preflight = "unavailable"
    func prepare(enabled: Bool = true) async throws {
        stop(); gate = MotionGate(); received = false; preflight = "unavailable"
        guard enabled else { preflight = "disabled"; return }
        guard manager.isDeviceMotionAvailable, manager.isGyroAvailable, manager.isAccelerometerAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.01
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.received = true
            let a = motion.userAcceleration, r = motion.rotationRate
            let at = MonotonicClock.now() + (motion.timestamp - ProcessInfo.processInfo.systemUptime) * 1000
            self.gate.sample(at: at, acceleration: sqrt(a.x*a.x+a.y*a.y+a.z*a.z)*9.80665, rotation: sqrt(r.x*r.x+r.y*r.y+r.z*r.z))
            self.report()
        }
        try await Task.sleep(for: .milliseconds(2200))
        preflight = !received ? "unavailable" : gate.ready ? "ready" : "unstable"
    }
    func gun(at: Double, result: @escaping (ReactionResult) -> Void) {
        gunAt = at; callback = result
        guard preflight == "ready" else { complete(ReactionResult(reactionMs: nil, reactionStatus: preflight)); return }
        report()
        if callback != nil { timeout = Task { do { try await Task.sleep(for: .seconds(30)); complete(ReactionResult(reactionMs: nil, reactionStatus: "timeout")) } catch {} } }
    }
    private func report() {
        guard let gunAt, let movement = gate.movedAt, callback != nil else { return }
        let ms = movement - gunAt
        guard (-120000...30000).contains(ms) else { return }
        complete(ReactionResult(reactionMs: ms, reactionStatus: ms < 100 ? "false_start" : "detected"))
    }
    private func complete(_ value: ReactionResult) { let action = callback; stop(); action?(value) }
    func end(status: String = "cancelled") {
        if callback != nil { complete(ReactionResult(reactionMs: nil, reactionStatus: status)) } else { stop() }
    }
    func stop() { manager.stopDeviceMotionUpdates(); timeout?.cancel(); timeout = nil; callback = nil; gunAt = nil }
}
