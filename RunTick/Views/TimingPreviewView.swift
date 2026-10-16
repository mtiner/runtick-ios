#if DEBUG
import SwiftUI

/// Isolated render fixtures for CI; no room sockets or business requests are started.
struct TimingPreviewView: View {
    @State private var model: RoomModel
    init(role: DeviceRole) {
        let user = User(id: role == .start ? 1 : 2, loginId: "RunTick")
        let room = RoomModel(code: "6960", user: user, api: APIClient(baseURL: AppConfiguration.serverURL))
        room.members = [Member(loginId: "RunTick", deviceRole: role, online: true)]
        room.connected = true; room.ready = true
        room.clock = ClockMapping(offset: 0, uncertaintyMs: 20, averageRttMs: 38,
                                  sampledAt: ProcessInfo.processInfo.systemUptime - (role == .finish ? 121 : 0))
        room.race = Race(id: "preview", status: "ready", createdAt: MonotonicClock.now(),
                         startAt: nil, finishAt: nil, elapsedMs: nil, uncertaintyMs: nil,
                         startUserId: 1, finishUserId: 2, savedResult: nil)
        _model = State(initialValue: room)
    }
    var body: some View { NavigationStack { RoomView(model: model, leave: {}).toolbar(.hidden, for: .navigationBar) } }
}
#endif
