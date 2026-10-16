import Foundation

/// Show the latest tap immediately; serialize writes so an older request cannot win.
struct RoleSelection {
    private(set) var optimistic: DeviceRole?
    private(set) var inFlight: DeviceRole?
    var saving: Bool { inFlight != nil }
    func displayed(serverRole: DeviceRole?) -> DeviceRole? { optimistic ?? serverRole }

    /// Returns true only when the caller needs to start draining the write queue.
    mutating func begin(_ target: DeviceRole, serverRole: DeviceRole?) -> Bool {
        guard target != displayed(serverRole: serverRole) else { return false }
        optimistic = target
        guard inFlight == nil else { return false }
        inFlight = target
        return true
    }
    mutating func succeeded(serverRole: DeviceRole?) {
        if optimistic != inFlight { inFlight = optimistic; return }
        inFlight = nil
        if serverRole == optimistic { optimistic = nil }
    }
    mutating func failed() {
        if optimistic != inFlight { inFlight = optimistic; return }
        optimistic = nil; inFlight = nil
    }
    mutating func receivedServerState(serverRole: DeviceRole?) {
        // Ignore old broadcasts until they actually confirm the latest selection.
        if !saving && serverRole == optimistic { optimistic = nil }
    }
}
