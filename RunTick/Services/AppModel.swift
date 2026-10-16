import SwiftUI

@MainActor @Observable final class AppModel {
    var api: APIClient?
    var user: User?
    var loading = false
    var lobbyReady = false
    var error = ""
    var room: RoomModel?
    let serverAddress = AppConfiguration.serverURL.absoluteString
    func configure() throws {
        api = APIClient(baseURL: AppConfiguration.serverURL)
        user = api?.savedUser
        api?.unauthorized = { [weak self] in self?.clearSession() }
    }
    func clearSession() { room?.stop(); room = nil; user = nil; lobbyReady = false; api?.clearCookies() }
    func restore() async {
        guard !serverAddress.isEmpty else { return }
        await perform {
            try self.configure()
            do {
                let result: UserResponse = try await self.api!.request("/api/auth/me")
                self.user = result.user; try self.api!.remember(result.user); try await self.leave()
            } catch let error as ClientError where error.status == 401 {
                // No saved session on a fresh install is expected, not a connection failure.
                return
            }
        }
    }
    func perform(_ action: () async throws -> Void) async {
        guard !loading else { return }; loading = true; error = ""
        defer { loading = false }
        do { try await action() } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func login(id: String, password: String) async throws {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else { throw ClientError.message("请输入用户 ID 和密码") }
        try configure()
        let result: UserResponse = try await api!.request("/api/auth/login", method: "POST", body: ["userId": id, "password": password])
        user = result.user; try api!.remember(result.user); try await leave()
    }
    func enter(code: String? = nil) async throws {
        guard let api, let user else { return }
        guard lobbyReady else { throw ClientError.message("请先重试退出旧房间，补交待发送事件") }
        if let code, code.count != 4 || !code.allSatisfy(\.isNumber) { throw ClientError.message("房间号必须为 4 位数字") }
        let path = code.map { "/api/rooms/\($0)/join" } ?? "/api/rooms"
        let response: RoomResponse = try await api.request(path, method: "POST")
        let model = RoomModel(code: response.room.code, user: user, api: api)
        room = model; lobbyReady = false; model.start()
    }
    /// Match the H5 room tab: resolve membership without leaving a live room.
    func openCurrentRoom() async throws {
        guard let api, let user else { return }
        let result: CurrentRoomResponse = try await api.request("/api/rooms/current")
        try Task.checkCancellation()
        if let current = result.room {
            guard room?.code != current.code else { room?.resume(); return }
            room?.stop()
            let model = RoomModel(code: current.code, user: user, api: api)
            room = model; lobbyReady = false; model.start()
        } else {
            try await leave()
        }
    }
    func replayPending() async throws {
        guard let api, let user else { return }
        let prefix = "pending:\(api.baseURL.absoluteString):\(user.id):"
        let legacyPrefix = "pending:\(api.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))):\(user.id):"
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix(prefix) || key.hasPrefix(legacyPrefix) {
            guard let bytes = value as? Data, let pending = try? JSONDecoder().decode(PendingEvent.self, from: bytes), pending.userId == user.id else { continue }
            let event = pending.event
            let _: RaceResponse = try await api.request("/api/rooms/\(pending.code)/races/\(pending.raceId)/events", method: "POST", body: ["kind": event.kind.rawValue, "at": event.at, "uncertaintyMs": event.uncertaintyMs])
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    func leave() async throws {
        guard let api else { return }
        try await replayPending()
        let _: EmptyResponse = try await api.request("/api/rooms/leave", method: "POST")
        room?.stop(); room = nil; lobbyReady = true
    }
    func logout() async {
        do { let _: EmptyResponse? = try await api?.request("/api/auth/logout", method: "POST") } catch { self.error = error.localizedDescription }
        clearSession()
    }
}

@MainActor @Observable final class RoomModel {
    let code: String; let user: User; let api: APIClient
    var members: [Member] = []; var connected = false; var ready = false
    var race: Race?; var clock: ClockMapping?; var syncing = false; var progress = 0
    var error = ""; var busy = false; var firing = false; var cue = ""; var pressed = false
    var volumeConfirmationPending = false
    var cueDeadline: Double?
    private var attemptedAutoStart: String?
    var pending: PendingEvent?; var submitting = false
    var stages: [StageDelay] { didSet { if stages.count == 3 && stages.allSatisfy(\.valid) { UserDefaults.standard.set(try? JSONEncoder().encode(stages), forKey: "starter") } } }
    private var tasks: [Task<Void, Never>] = []
    private var audio = StarterAudio()
    private var eventClock: ClockMapping?
    private var socket: URLSessionWebSocketTask?
    private var stopped = false
    private var receivedRoomState = false
    private var autoRetry = true
    private var retryAfter: Double = 0
    private(set) var roleSelection = RoleSelection()
    var serverRole: DeviceRole? { members.first { $0.loginId == user.loginId }?.deviceRole }
    var role: DeviceRole? { roleSelection.displayed(serverRole: serverRole) }
    func displayedRole(for member: Member) -> DeviceRole? {
        guard let selected = roleSelection.optimistic else { return member.deviceRole }
        return member.loginId == user.loginId ? selected : (selected == .start ? .finish : .start)
    }
    var roleSaving: Bool { roleSelection.saving }
    var raceRole: DeviceRole? { guard let race else { return nil }; return race.startUserId == user.id ? .start : race.finishUserId == user.id ? .finish : nil }
    var pendingKey: String { "pending:\(api.baseURL.absoluteString):\(user.id):\(code)" }
    init(code: String, user: User, api: APIClient) {
        self.code = code; self.user = user; self.api = api
        let saved = UserDefaults.standard.data(forKey: "starter").flatMap { try? JSONDecoder().decode([StageDelay].self, from: $0) }
        stages = saved?.count == 3 ? saved!.map(\.normalized) : StageDelay.defaults
        pending = UserDefaults.standard.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode(PendingEvent.self, from: $0) }
    }
    func start() {
        tasks.append(Task { await calibrate() })
        tasks.append(Task {
            do { let detail: RoomDetail = try await api.request("/api/rooms/\(code)"); if !receivedRoomState { members = detail.members } } catch { self.error = error.localizedDescription }
            while !Task.isCancelled {
                do {
                    let result: RaceResponse = try await api.request("/api/rooms/\(code)/races")
                    if let race = result.race { update(race) }
                    if pending != nil && autoRetry && ProcessInfo.processInfo.systemUptime >= retryAfter { await submit() }
                } catch is CancellationError { break } catch {
                    let status = (error as? ClientError)?.status ?? 0
                    // A temporary transport failure must not interrupt local timing.
                    if !(race?.active == true && clock != nil && (status == 0 || status >= 500)) { self.error = error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        })
        tasks.append(Task { await socketLoop() })
    }
    func update(_ value: Race) {
        if let race, !race.accepts(value) { return }
        race = value
        if !value.active { interrupt() }
    }
    func stop() { stopped = true; tasks.forEach { $0.cancel() }; tasks.removeAll(); socket?.cancel(with: .goingAway, reason: nil); socket = nil; connected = false; interrupt() }
    func interrupt() { pressed = false; eventClock = nil; audio.stop(); firing = false; volumeConfirmationPending = false; cue = ""; cueDeadline = nil }
    func resume() { if race?.active == true && clock?.fresh != true { tasks.append(Task { await calibrate() }) }; socket?.sendPing { _ in } }
    func action(_ body: () async throws -> Void) async {
        guard !busy else { return }; busy = true; error = ""; defer { busy = false }
        do { try await body() } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func calibrate() async {
        guard !syncing, !pressed, !firing else { return }; syncing = true; progress = 0; error = ""; defer { syncing = false }
        do {
            var samples: [ClockSample] = []
            for i in 0..<20 {
                try Task.checkCancellation()
                let sent = MonotonicClock.now()
                let response: ClockResponse = try await api.request("/api/clock?clientSentAt=\(sent)&nonce=\(UUID().uuidString)")
                let received = MonotonicClock.now()
                guard response.clientSentAt == sent, response.sentAt >= response.receivedAt, response.processingMs == response.sentAt - response.receivedAt, received - sent >= response.processingMs else { throw ClientError.message("校时响应无效，请重试") }
                samples.append(ClockSample(sent: sent, received: received, serverReceived: response.receivedAt, serverSent: response.sentAt)); progress = i + 1
            }
            clock = try ClockMapping.average(samples)
        } catch { if clock?.fresh != true { clock = nil }; if !(error is CancellationError) { self.error = error.localizedDescription } }
    }
    func pick(_ target: DeviceRole) async {
        guard race?.active != true, connected, !busy, !stopped,
              roleSelection.begin(target, serverRole: serverRole) else { return }
        error = ""
        while let target = roleSelection.inFlight {
            do {
                let _: EmptyResponse = try await api.request("/api/rooms/\(code)/role", method: "POST", body: ["deviceRole": target.rawValue])
                roleSelection.succeeded(serverRole: serverRole)
            } catch {
                roleSelection.failed()
                // An obsolete request failure must not roll back or alert over a newer tap.
                if !roleSelection.saving && !stopped && !(error is CancellationError) { self.error = error.localizedDescription }
            }
            if stopped { return }
        }
        try? await socket?.send(.string("{\"type\":\"sync\"}"))
    }
    func raceAction(_ suffix: String = "") async {
        await action {
            let path = "/api/rooms/\(code)/races" + (suffix.isEmpty ? "" : "/\(race!.id)/\(suffix)")
            let result: RaceResponse = try await api.request(path, method: "POST")
            if let race = result.race { update(race) }
        }
    }
    func beginRecording() async {
        guard ready, connected, role != nil, !roleSaving, clock?.fresh == true, !syncing else {
            error = roleSaving ? "角色正在后台同步，请稍后开始记录。" : "请等待两端就绪并完成校时，再开始记录。"; return
        }
        await action {
            let settings = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stages))
            let result: RaceResponse = try await api.request("/api/rooms/\(code)/races", method: "POST", body: ["starterSettings": settings])
            if let race = result.race {
                guard race.starterSettings != nil else { throw ClientError.message("服务器尚未支持双端开始记录，请更新 API 服务后重试。") }
                update(race)
            }
        }
    }
    func autoFire() async {
        guard let race, raceRole == .start, race.active, race.startAt == nil,
              attemptedAutoStart != race.id, let settings = race.starterSettings,
              settings.count == 3, settings.allSatisfy(\.valid) else { return }
        if clock?.fresh != true { await calibrate() }
        guard clock?.fresh == true, !Task.isCancelled else { return }
        attemptedAutoStart = race.id
        stages = settings
        await fire()
    }
    func fire(allowReducedVolume: Bool = false) async {
        guard let clock, clock.fresh, !syncing, !firing, race?.active == true, race?.startAt == nil, pending == nil, raceRole == .start else { if self.clock?.fresh != true { await calibrate(); error = "校时已更新，请再次发令" }; return }
        firing = true; let snapshot = clock
        defer { firing = false; cueDeadline = nil }
        do {
            // Both local and remote starts ask on the phone that actually plays the cues.
            if !allowReducedVolume {
                if try audio.needsVolumeConfirmation() {
                    volumeConfirmationPending = true
                    return
                }
            }
            try await audio.play(settings: stages, cue: { self.cue = $0; self.cueDeadline = $1 }, gun: { at, extra in self.capture(.start, at: at, clock: snapshot, extra: extra) })
        }
        catch is CancellationError {} catch { self.error = error.localizedDescription; audio.stop() }
    }
    func press() {
        if clock?.fresh == false { error = "校时已过期，请先重新校时，再按住屏幕。"; return }
        guard let clock, clock.fresh, !syncing, pending == nil, race?.active == true, race?.finishAt == nil, raceRole == .finish else { return }
        eventClock = clock; pressed = true
    }
    func release(at: Double) {
        guard pressed, let eventClock else { return }; pressed = false; self.eventClock = nil
        guard race?.active == true else { return }; capture(.finish, at: at, clock: eventClock)
    }
    func cancelPress() { pressed = false; eventClock = nil }
    private func capture(_ kind: DeviceRole, at: Double, clock: ClockMapping, extra: Double = 0) {
        guard pending == nil, let race else { return }
        autoRetry = true
        pending = PendingEvent(code: code, raceId: race.id, userId: user.id, event: TimingEvent(kind: kind, at: at + clock.offset, uncertaintyMs: clock.uncertaintyMs + extra))
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: pendingKey)
        tasks.append(Task { await submit() })
    }
    func submit() async {
        guard let pending, !submitting, !stopped else { return }; submitting = true; defer { submitting = false }
        do {
            let event = pending.event
            let result: RaceResponse = try await api.request("/api/rooms/\(code)/races/\(pending.raceId)/events", method: "POST", body: ["kind": event.kind.rawValue, "at": event.at, "uncertaintyMs": event.uncertaintyMs])
            self.pending = nil; UserDefaults.standard.removeObject(forKey: pendingKey)
            if let race = result.race { update(race) }
        } catch {
            self.error = error.localizedDescription + "；原始时间戳已保留"
            let status = (error as? ClientError)?.status ?? 0
            autoRetry = status == 0 || status >= 500
            retryAfter = ProcessInfo.processInfo.systemUptime + 3
        }
    }
    func save(distance: Int) async {
        guard (1...100000).contains(distance), let race else { error = "请输入 1–100000 米的整数距离"; return }
        await action {
            let result: SaveResponse = try await api.request("/api/rooms/\(code)/races/\(race.id)/result", method: "POST", body: ["distance": distance])
            var value = self.race ?? race
            value.savedResult = SavedResult(distance: result.result.distance, isPb: result.result.isPb, pbImprovementMs: result.result.pbImprovementMs)
            update(value)
        }
    }
    private func socketLoop() async {
        var retry = 0
        while !Task.isCancelled && !stopped {
            let ws = api.session.webSocketTask(with: api.socketRequest(code: code)); socket = ws; ws.resume()
            let heartbeat = Task { while !Task.isCancelled { do { try await Task.sleep(for: .seconds(30)); try await ws.send(.string("{\"type\":\"ping\"}")) } catch { break } } }
            do {
                try await ws.send(.string("{\"type\":\"sync\"}"))
                while !Task.isCancelled {
                    let message = try await ws.receive()
                    let data: Data
                    switch message { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: continue }
                    guard let event = try? JSONDecoder().decode(HubState.self, from: data), event.type == "state" else { continue }
                    connected = true; retry = 0; receivedRoomState = true; members = event.members ?? []; roleSelection.receivedServerState(serverRole: serverRole); ready = event.ready ?? false
                }
            } catch { connected = false; ready = false }
            heartbeat.cancel(); ws.cancel(with: .goingAway, reason: nil)
            if Task.isCancelled || stopped { break }
            retry += 1
            do { try await Task.sleep(for: .seconds(min(pow(2, Double(min(retry, 4))), 10))) } catch { break }
        }
    }
}
