import SwiftUI
import Network

@MainActor @Observable final class AppModel {
    var api: APIClient?
    var user: User?
    var loading = false
    var lobbyReady = false
    var error = ""
    var room: RoomModel?
    var syncNotice = ""
    private var syncTask: Task<Void, Never>?
    private var syncGeneration = UUID()
    private var profileRevision = UUID()
    private let injectedClient: Bool
    init(api: APIClient? = nil) { self.api = api; injectedClient = api != nil }
    let serverAddress = AppConfiguration.serverURL.absoluteString
    func configure(reset: Bool = false) throws {
        if api == nil || (reset && !injectedClient) { api = APIClient(baseURL: AppConfiguration.serverURL) }
        user = api?.savedUser
        if let client = api {
            client.unauthorized = { [weak self, weak client] in
                guard let self, let client, self.api === client else { return }
                self.clearSession()
            }
        }
    }
    func clearSession() { profileRevision = UUID(); syncGeneration = UUID(); syncTask?.cancel(); syncTask = nil; syncNotice = ""; room?.stop(); room = nil; user = nil; lobbyReady = false; api?.clearCookies() }
    func restore() async {
        guard !serverAddress.isEmpty else { return }
        await perform {
            try self.configure()
            do {
                let result: UserResponse = try await self.api!.request("/api/auth/me")
                self.user = result.user; try self.api!.remember(result.user); self.lobbyReady = true; self.scheduleSync()
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
        try configure(reset: true)
        let result: UserResponse = try await api!.request("/api/auth/login", method: "POST", body: ["userId": id, "password": password])
        user = result.user; try api!.remember(result.user); lobbyReady = true; scheduleSync()
    }
    func updateAvatar(_ filename: String) async throws {
        guard let client = api, let current = user else { throw ClientError.message("请先登录") }
        let revision = UUID(); profileRevision = revision
        let result: UserResponse = try await client.request("/api/auth/avatar", method:"PATCH",body:["avatar":filename])
        try Task.checkCancellation()
        guard profileRevision == revision, api === client, user?.id == current.id, result.user.id == current.id else { throw CancellationError() }
        user = result.user
        room?.updateProfileAvatar(result.user.avatar)
        try client.remember(result.user)
    }
    func refreshProfile() async throws {
        guard let client = api, let current = user else { return }
        let revision = profileRevision
        let result: UserResponse = try await client.request("/api/auth/me")
        guard profileRevision == revision, api === client, user?.id == current.id, result.user.id == current.id else { return }
        user = result.user; room?.updateProfileAvatar(result.user.avatar); try client.remember(result.user)
    }
    func enter(code: String? = nil) async throws {
        guard let api, let user else { return }
        guard lobbyReady else { throw ClientError.message("暂时无法确认房间状态，请重试恢复房间。") }
        if let code, code.count != 4 || !code.allSatisfy(\.isNumber) { throw ClientError.message("房间号必须为 4 位数字") }
        let path = code.map { "/api/rooms/\($0)/join" } ?? "/api/rooms"
        let response: RoomResponse = try await api.request(path, method: "POST")
        let model = RoomModel(code: response.room.code, user: user, api: api)
        room = model; lobbyReady = false; model.start()
    }
    /// Match the H5 room tab: resolve membership without leaving a live room.
    func openCurrentRoom() async throws {
        // A login session never implicitly restores room membership on cold launch.
        if let room { room.resume() } else { lobbyReady = true }
    }
    var syncingRecords: Bool { syncTask != nil }
    func scheduleSync(showConfirmation: Bool = false) {
        guard syncTask == nil else { return }
        let token = UUID(); syncGeneration = token
        syncTask = Task {
            await replayPending()
            guard syncGeneration == token, !Task.isCancelled else { return }
            if showConfirmation && syncNotice.isEmpty && user != nil { syncNotice = "本机训练记录已同步。" }
            syncTask = nil
        }
    }
    func replayPending() async {
        guard let api, let user else { return }
        await TrainingSync.retry(api: api, userId: user.id)
        let prefix = "pending:\(api.baseURL.absoluteString):\(user.id):"
        let legacyPrefix = "pending:\(api.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))):\(user.id):"
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix(prefix) || key.hasPrefix(legacyPrefix) {
            guard let bytes = value as? Data, let pending = try? JSONDecoder().decode(PendingEvent.self, from: bytes), pending.userId == user.id else { continue }
            let event = pending.event
            guard !Task.isCancelled, self.user?.id == user.id else { return }
            do {
                let _: RaceResponse = try await api.request("/api/rooms/\(pending.code)/races/\(pending.raceId)/events", method: "POST", body: event.body)
                if UserDefaults.standard.data(forKey: key) == bytes { UserDefaults.standard.removeObject(forKey: key) }
                if room?.pending?.raceId == pending.raceId { room?.pending = nil }
            } catch is CancellationError { return }
            catch { if ((error as? ClientError)?.status ?? 0) == 0 || ((error as? ClientError)?.status ?? 0) >= 500 { break } }
        }
        guard self.user?.id == user.id else { return }
        let remaining = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) || $0.hasPrefix(legacyPrefix) || $0.hasPrefix(TrainingSync.prefix(api, user.id)) }.count
        syncNotice = remaining == 0 ? "" : "有 \(remaining) 条训练记录尚未同步，已保留在此设备上。请联网后重试。"
    }
    func leave() async throws {
        guard let api else { return }
        let _: EmptyResponse = try await api.request("/api/rooms/leave", method: "POST")
        room?.stop(); room = nil; lobbyReady = true; scheduleSync()
    }
    func logout() async {
        do { let _: EmptyResponse? = try await api?.request("/api/auth/logout", method: "POST") } catch { self.error = error.localizedDescription }
        clearSession()
    }
}

@MainActor @Observable final class RoomModel {
    let code: String; private(set) var user: User; let api: APIClient
    func updateProfileAvatar(_ filename: String?) {
        user.avatar = filename
        members = members.map { member in
            var updated = member
            if member.loginId == user.loginId { updated.avatar = filename }
            return updated
        }
    }
    var members: [Member] = []; var connected = false; var ready = false
    var race: Race?; var clock: ClockMapping?; var syncing = false; var progress = 0
    var error = ""; var busy = false; var firing = false; var cue = ""; var pressed = false
    var volumeConfirmationPending = false
    var cueDeadline: Double?
    private var attemptedAutoStart: String?
    private var recordingClock: ClockMapping?
    private var fireGeneration = UUID()
    private var started = false
    var pending: PendingEvent?; var submitting = false
    var stages = StageDelay.defaults
    private var tasks: [Task<Void, Never>] = []
    private var audio = StarterAudio()
    var reactionNotice = ""
    private var reactionMotion = ReactionMotion()
    private var eventClock: ClockMapping?
    private var stopped = false
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
        pending = UserDefaults.standard.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode(PendingEvent.self, from: $0) }
    }
    func start() {
        guard !started, !stopped else { return }; started = true
        if clock == nil, let cached = AppTimeSync.latest, cached.fresh { clock = cached }
        tasks.append(Task { if clock?.fresh != true { await calibrate() } })
        let monitor = NWPathMonitor(); pathMonitor = monitor
        var initial = true
        monitor.pathUpdateHandler = { [weak self] _ in
            if initial { initial = false; return }
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.needsResync = true
                if self.clock?.fresh != true { await self.calibrate() }
            }
        }
        monitor.start(queue:DispatchQueue(label:"cc.runtick.network"))
        tasks.append(Task {
            while !Task.isCancelled && !stopped {
                do {
                    let state: RoomPoll = try await api.request("/api/rooms/\(code)/state",method:"POST")
                    connected = true; members = state.members; ready = state.ready
                    roleSelection.receivedServerState(serverRole:serverRole)
                    if let value = state.race { update(value) }
                    else { archivePendingFromPreviousRound() }
                    if race?.active != true && !busy && !editingSettings { stages = state.starterSettings }
                    if pending != nil && autoRetry && ProcessInfo.processInfo.systemUptime >= retryAfter { await submit() }
                } catch is CancellationError { break }
                catch { connected = false; ready = false; print("RunTick room poll: \(error.localizedDescription)") }
                do { try await Task.sleep(for:.milliseconds(connected ? (race?.active == true ? 500 : 1000) : 3000)) } catch { break }
            }
        })
    }
    func update(_ value: Race) {
        var value = value
        if race?.id == value.id && value.reactionStatus == nil { value.reactionStatus = race?.reactionStatus; value.reactionMs = race?.reactionMs }
        if let race, !race.accepts(value) { return }
        if let pending, pending.raceId != value.id || !value.active { archivePendingFromPreviousRound() }
        if race?.id != value.id { recordingClock = value.active && clock?.fresh == true ? clock : nil }
        if value.active && recordingClock == nil && clock?.fresh == true { recordingClock = clock }
        race = value
        if !value.active { recordingClock = nil; interrupt() }
    }
    private func archivePendingFromPreviousRound() {
        guard let old = pending else { return }
        if let bytes = UserDefaults.standard.data(forKey: pendingKey) {
            UserDefaults.standard.set(bytes, forKey: pendingKey + ":" + old.raceId)
            UserDefaults.standard.removeObject(forKey: pendingKey)
        }
        pending = nil
    }
    func stop() { pathMonitor?.cancel(); pathMonitor = nil; stopped = true; tasks.forEach { $0.cancel() }; tasks.removeAll(); connected = false; interrupt() }
    func interrupt() { fireGeneration = UUID(); pressed = false; eventClock = nil; audio.stop(); reactionMotion.end(status: race?.status == "completed" ? "timeout" : "cancelled"); firing = false; volumeConfirmationPending = false; cue = ""; cueDeadline = nil }
    func resume() {
        // Reopening the same room and transient inactive/active changes do not
        // invalidate a valid monotonic-to-UTC mapping.
        if clock?.fresh != true && (race?.active != true || recordingClock == nil) {
            tasks.append(Task { await calibrate() })
        }

    }
    func action(_ body: () async throws -> Void) async {
        guard !busy else { return }; busy = true; error = ""; defer { busy = false }
        do { try await body() } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    var editingSettings = false
    var allowHTTPFallback = false
    var syncError = ""
    var syncDetail = ""
    var latestSyncRtt: Double?
    var averageSyncRtt: Double?
    var syncTarget: Int { AppTimeSync.target }
    private var needsResync = false
    private var pathMonitor: NWPathMonitor?
    var syncSummary: String {
        if syncing { return "正在校准 \(progress)/\(syncTarget)" }
        guard let value = recordingClock ?? clock else { return syncError.isEmpty ? "尚未同步时间" : "时间同步失败，请重试" }
        if !value.fresh { return "时间同步已过期，请重新同步" }
        return syncError.isEmpty ? "时间已同步" : "时间同步质量下降，请重新同步"
    }
    func calibrate(force: Bool = false) async {
        guard !syncing, !pressed, !firing else { return }; syncing = true; progress = 0; defer { syncing = false }
        do {
            do { if needsResync || force { AppTimeSync.invalidate() }; clock = try await AppTimeSync.synchronize(detail: { self.syncDetail = $0; self.latestSyncRtt = SuningTimeClient.shared.latestRTT; self.averageSyncRtt = SuningTimeClient.shared.averageRTT; print("RunTick time sync: \($0)") }) { self.progress = $0 }; syncError = ""; needsResync = false }
            catch {
                guard allowHTTPFallback, !(error is CancellationError) else { throw error }
                clock = try await httpFallback(); syncError = "主时间源不可用，使用应用 API HTTP 备用源"; needsResync = false
            }
            if let value = clock { latestSyncRtt = SuningTimeClient.shared.latestRTT ?? value.averageRttMs; averageSyncRtt = SuningTimeClient.shared.averageRTT ?? value.averageRttMs; print("RunTick sync server=\(value.server) samples=\(value.validSamples) RTT=\(value.averageRttMs) offset=\(value.offset) age=\(value.ageMs) estimatedUncertainty=\(value.estimatedUncertaintyMs)") }
            if race?.active == true && recordingClock == nil { recordingClock = clock }
        } catch { if !(error is CancellationError) { syncError = error.localizedDescription; print("RunTick time sync failed: \(syncError)") } }
    }
    private func httpFallback() async throws -> ClockMapping {
        var samples: [ClockSample] = []
        for _ in 0..<8 {
            try Task.checkCancellation()
            let sent = MonotonicClock.now()
            let response: ClockResponse = try await api.request("/api/clock?clientSentAt=\(sent)&nonce=\(UUID().uuidString)")
            let received = MonotonicClock.now()
            guard response.clientSentAt == sent, response.sentAt >= response.receivedAt,
                  response.processingMs == response.sentAt-response.receivedAt,
                  received-sent >= response.processingMs else { throw ClientError.message("HTTP 降级响应无效") }
            samples.append(ClockSample(sent:sent,received:received,serverReceived:response.receivedAt,serverSent:response.sentAt))
            try await Task.sleep(nanoseconds:100_000_000)
        }
        var value = try NtpQuality.select(samples)
        let offsets = samples.map { (($0.serverReceived-$0.sent)+($0.serverSent-$0.received))/2 }
        guard offsets.max()! - offsets.min()! <= 10 else { throw ClientError.message("HTTP 降级质量不足") }
        value.server = "HTTP"; value.validSamples = samples.count
        return value
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

    }
    func raceAction(_ suffix: String = "") async {
        await action {
            guard suffix.isEmpty || race != nil else { throw ClientError.message("当前没有可继续的训练，请返回房间重试。") }
            let path = "/api/rooms/\(code)/races" + (suffix.isEmpty ? "" : "/\(race!.id)/\(suffix)")
            let result: RaceResponse = try await api.request(path, method: "POST")
            if let race = result.race { update(race) }
        }
    }
    func stageText(at now: Double = MonotonicClock.now()) -> String {
        if race?.startAt != nil { return "计时中" }
        guard let clock = recordingClock ?? clock, let points = race?.cueTimeline else { return "等待发令" }
        let utc=clock.utcAt(now)
        guard let point=points.last(where:{$0.at<=utc}) else { return "等待发令" }
        return ["各就各位","预备","枪声"][min(2,max(0,point.stage))]
    }
    func beginRecording(playSet: Bool = true) async {
        guard pending == nil else { error = "上一轮计时记录尚未同步，请重新同步后再开始。"; return }
        if needsResync || clock?.fresh != true { await calibrate() }
        guard clock?.fresh == true, !syncing else { return }
        guard ready, connected, role != nil, !roleSaving else {
            error = roleSaving ? "角色正在后台同步，请稍后开始记录。" : "请等待两端就绪并完成校时，再开始记录。"; return
        }
        await action {
            let result: RaceResponse = try await api.request("/api/rooms/\(code)/races", method: "POST", body: ["playSet": playSet])
            if let race = result.race {
                guard race.starterSettings != nil else { throw ClientError.message("发令设置暂时未能同步，请返回房间重试。") }
                update(race)
            }
        }
    }
    func autoFire() async {
        guard let race, raceRole == .start, race.active, race.startAt == nil,
              attemptedAutoStart != race.id, let settings = race.starterSettings else { return }
        guard settings.count == 3, settings.allSatisfy(\.valid) else { error = "本轮发令设置超出 0～10 秒整数范围，暂无法发令。请重新创建房间并使用此范围设置。"; return }
        if clock?.fresh != true { await calibrate() }
        guard clock?.fresh == true, !Task.isCancelled else { return }
        reactionNotice = ""
        attemptedAutoStart = race.id
        stages = settings
        await fire()
    }
    func fire(allowReducedVolume: Bool = false) async {
        if let shared = race?.starterSettings {
            guard shared.count == 3, shared.allSatisfy(\.valid) else { error = "本轮发令设置超出 0～10 秒整数范围，暂无法发令。请重新创建房间并使用此范围设置。"; return }
            stages = shared
        }
        guard let clock, clock.fresh, !syncing, !firing, race?.active == true, race?.startAt == nil, pending == nil, raceRole == .start else { if self.clock?.fresh != true { await calibrate(); if self.clock?.fresh == true { syncDetail = "时间校准已完成，请再次发令。" } }; return }
        firing = true; let snapshot = recordingClock ?? clock
        let token = UUID(); fireGeneration = token
        let raceId = race!.id
        defer { if fireGeneration == token { firing = false; cueDeadline = nil } }
        do {
            // Both local and remote starts ask on the phone that actually plays the cues.

            cue = "等待发令…"
            try? await reactionMotion.prepare(enabled: stages[0].reactionEnabled == true)
            try Task.checkCancellation()
            guard fireGeneration == token, !stopped, race?.id == raceId, race?.active == true else { return }
            try await audio.play(settings: stages, scheduledTimes: race?.cueTimeline?.map { point in let now=MonotonicClock.now(); return now + point.at - snapshot.utcAt(now) }, cue: { self.cue = $0; self.cueDeadline = $1 }, gun: { at, extra in
                guard self.fireGeneration == token, self.race?.id == raceId else { return }
                self.capture(.start, at: at, clock: snapshot, extra: extra)
                guard let raceId = self.race?.id else { return }
                self.reactionMotion.gun(at: at) { result in
                    if self.race?.id == raceId { self.race?.reactionMs = result.reactionMs; self.race?.reactionStatus = result.reactionStatus }
                    Task {
                        do { try await TrainingSync.send(api: self.api, userId: self.user.id, path: "/api/rooms/\(self.code)/races/\(raceId)/reaction", body: ["reactionMs": result.reactionMs as Any? ?? NSNull(), "reactionStatus": result.reactionStatus], id: raceId) }
                        catch { self.reactionNotice = "反应时暂未同步，已保留在本机；正式计时不受影响。" }
                    }
                }
            })
        }
        catch {
            if fireGeneration == token {
                audio.stop(); reactionMotion.end()
                if !(error is CancellationError) { self.error = "发令未完成，请检查声音输出后重试。" }
            }
        }
    }
    var hasRecordingClock: Bool { recordingClock != nil || clock?.fresh == true }
    func press() {
        let snapshot = recordingClock ?? (clock?.fresh == true ? clock : nil)
        guard let clock = snapshot else { error = "请先完成时间校准，再开始计时。"; return }
        guard !syncing, pending == nil, race?.active == true, race?.finishAt == nil, raceRole == .finish else { return }
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
        pending = PendingEvent(code: code, raceId: race.id, userId: user.id, event: TimingEvent(kind: kind, at: clock.utcAt(at), uncertaintyMs: clock.estimatedUncertaintyMs + extra, monoNanos: String(MonotonicClock.nanosAt(at)), deviceId: DeviceIdentity.value, sessionId: race.id, syncServer: clock.server, syncRttMs: clock.averageRttMs, syncAgeMs: clock.ageMs, syncOffsetMs: clock.offset, syncSource: clock.syncSource))
        if let event = pending, let bytes = try? JSONEncoder().encode(event) {
            let key = "runtick.eventDiagnostics"
            var audit = UserDefaults.standard.array(forKey:key) as? [Data] ?? []
            audit.append(bytes); UserDefaults.standard.set(Array(audit.suffix(200)),forKey:key)
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: pendingKey)
        tasks.append(Task { await submit() })
    }
    func submit() async {
        guard let pending, !submitting, !stopped else { return }; submitting = true; defer { submitting = false }
        let savedBytes = UserDefaults.standard.data(forKey: pendingKey)
        do {
            let event = pending.event
            let result: RaceResponse = try await api.request("/api/rooms/\(code)/races/\(pending.raceId)/events", method: "POST", body: event.body)
            if self.pending?.raceId == pending.raceId { self.pending = nil }
            if UserDefaults.standard.data(forKey: pendingKey) == savedBytes { UserDefaults.standard.removeObject(forKey: pendingKey) }
            if let race = result.race { update(race) }
        } catch is CancellationError { return }
        catch {
            guard self.pending?.raceId == pending.raceId else { return }
            self.error = "计时记录暂未同步，已保留在此设备上。请联网后重试。"
            let status = (error as? ClientError)?.status ?? 0
            autoRetry = status == 0 || status >= 500
            retryAfter = ProcessInfo.processInfo.systemUptime + 3
        }
    }
    func save(distance: Int) async {
        guard (1...100000).contains(distance), let race else { error = "请输入 1–100000 米的整数距离"; return }
        await action {
            let result: SaveResponse = try await api.request("/api/rooms/\(code)/races/\(race.id)/result", method: "POST", body: ["distance": distance])
            guard var value = self.race, value.id == race.id else { return }
            value.savedResult = SavedResult(distance: result.result.distance, isPb: result.result.isPb, pbImprovementMs: result.result.pbImprovementMs)
            update(value)
        }
    }
}
