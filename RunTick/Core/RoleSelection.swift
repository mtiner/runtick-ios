import Foundation

/// Optimistic selection is separate from authoritative room membership.
struct RoleSelection {
    private(set) var optimistic: DeviceRole?
    private(set) var saving = false
    func displayed(serverRole: DeviceRole?) -> DeviceRole? { optimistic ?? serverRole }
    mutating func begin(_ target: DeviceRole, serverRole: DeviceRole?) -> Bool {
        guard !saving, target != displayed(serverRole: serverRole) else { return false }
        optimistic = target; saving = true
        return true
    }
    mutating func succeeded(serverRole: DeviceRole?) {
        saving = false
        if serverRole == optimistic { optimistic = nil }
    }
    mutating func failed() { optimistic = nil; saving = false }
    mutating func receivedServerState() {
        // Preserve the local highlight while the request is in flight. Once the
        // request completes, the next room state supersedes the optimistic value.
        if !saving { optimistic = nil }
    }
}
