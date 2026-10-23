import SwiftUI

@MainActor @Observable final class SoloStartModel {
    let api: APIClient; let user: User
    var stages = StageDelay.defaults
    var running = false; var cue = ""; var deadline: Double?; var error = ""
    var result: ReactionResult?; var volumeWarning = false
    private let audio = StarterAudio(); private let motion = ReactionMotion()
    private var task: Task<Void, Never>?
    private var previousIdleTimer = false
    private var generation = UUID()
    init(api: APIClient, user: User) {
        self.api = api; self.user = user

    }
    var settingsLoaded = false
    func loadSettings() async {
        settingsLoaded = false
        do { let value: StarterSettingsResponse = try await api.request("/api/auth/starter-settings"); stages = value.starterSettings; settingsLoaded = true }
        catch { self.error = error.localizedDescription }
    }
    func start(allowReducedVolume: Bool = false) {
        guard settingsLoaded, !running, stages.count == 3, stages.allSatisfy(\.valid) else { return }
        do { if !allowReducedVolume, try audio.needsVolumeConfirmation() { volumeWarning = true; return } }
        catch { self.error = error.localizedDescription; return }
        previousIdleTimer = UIApplication.shared.isIdleTimerDisabled; UIApplication.shared.isIdleTimerDisabled = true
        running = true; result = nil; error = ""; cue = "等待发令…"
        generation = UUID(); let token = generation
        let id = UUID().uuidString, saved = stages
        task = Task {
            do {
                try? await motion.prepare(enabled: saved[0].reactionEnabled == true); try Task.checkCancellation()
                try await audio.play(settings: saved, cue: { self.cue = $0; self.deadline = $1 }, gun: { at, _ in
                    let firedAt = at
                    self.motion.gun(at: at) { value in
                        self.result = value
                        Task {
                            do {
                                let settings = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved))
                                try await TrainingSync.send(api: self.api, userId: self.user.id, path: "/api/starts", body: ["id": id, "firedAt": firedAt, "athleteId": self.user.id, "settings": settings, "reactionMs": value.reactionMs as Any? ?? NSNull(), "reactionStatus": value.reactionStatus], id: id)
                            } catch { self.error = "记录已保留在本机，联网后可重试：" + error.localizedDescription }
                        }
                    }
                })
                deadline = nil
            } catch is CancellationError {} catch { if generation == token { self.error = "发令未完成，请检查声音输出后重试。"; stop() } }
        }
    }
    func stop() { generation = UUID(); if running { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }; task?.cancel(); motion.end(); audio.stop(); running = false; deadline = nil; volumeWarning = false }
}
struct SoloStartView: View {
    @State private var model: SoloStartModel
    @State private var confirmCue = false
    @Environment(\.scenePhase) private var phase
    init(api: APIClient, user: User) { _model = State(initialValue: SoloStartModel(api: api, user: user)) }
    var body: some View {
        RTPage {
            RTBrand()
            RTHero(badge: "单人训练", title: "起跑发令", subtitle: "为每一次认真训练而生")
            if model.running {
                RTCard {
                    Text(model.cue).font(.largeTitle.bold()).frame(maxWidth: .infinity)
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        if let deadline = model.deadline { Text("\(max(0, Int(ceil((deadline - MonotonicClock.now()) / 1000))))").font(.system(size: 86, weight: .bold, design: .rounded)).monospacedDigit().frame(maxWidth: .infinity) }
                    }
                    if let result = model.result { if result.reactionStatus == "false_start" { RTChip(text: "抢跑", lemon: true) }; Text(result.text).font(.title2).frame(maxWidth: .infinity) }
                    Button("结束本轮") { model.stop() }
                }
            } else {
                RTNotice(text: "发令时间使用“我的—起跑设置”。仅在枪声后检测移动，检测失败不影响计时。")
                AudioPreparationCard()
                Text("枪声前可调整手机，枪声后检测到移动即记录反应时。反应时为手机运动检测估算，非专业起跑器计时。保持 App 在前台；后台切换会中断检测。").font(.footnote).foregroundStyle(RT.muted)
                Button("开始发令") { Task { await model.loadSettings(); if model.settingsLoaded { confirmCue = true } } }.buttonStyle(RTButtonStyle())
            }
            NavigationLink("单人起跑记录") { SoloHistoryView(api: model.api) }
            Button("重试同步本机记录") { Task { await TrainingSync.retry(api: model.api, userId: model.user.id) } }
        }
        .confirmationDialog("本轮播放“各就各位”？", isPresented: $confirmCue, titleVisibility: .visible) {
            Button("播放并开始") { model.stages[0].enabled = true; model.start() }
            Button("跳过并开始") { model.stages[0].enabled = false; model.start() }
            Button("取消", role: .cancel) {}
        }
        .alert("媒体音量未调至最大", isPresented: $model.volumeWarning) {
            Button("先调整音量", role: .cancel) {}
            Button("仍然开始") { model.start(allowReducedVolume: true) }
        } message: { Text("建议调高媒体音量，以便听到口令和枪声。也可以按当前音量继续。") }
        .rtErrorAlert($model.error, enabled: !model.volumeWarning)
        .onChange(of: phase) { _, value in if value != .active { model.stop() } }
        .onDisappear { model.stop() }
        .task { await TrainingSync.retry(api: model.api, userId: model.user.id) }
    }
}
struct SoloHistoryView: View {
    let api: APIClient
    @State private var records: [SoloRecord] = []
    @State private var hasMore = false; @State private var loading = false; @State private var error = ""
    var body: some View {
        RTPage {
            RTBrand(); RTHero(badge: "训练档案", title: "单人起跑记录", subtitle: "手机运动检测估算 · 不计入距离成绩或 PB")
            RTCard {
                if records.isEmpty { Text("暂无记录") }
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        if record.reactionStatus == "false_start" { RTChip(text: "抢跑", lemon: true) }
                        Text(ReactionResult.text(record.reactionMs, record.reactionStatus)).font(.headline)
                        Text(Date(timeIntervalSince1970: record.createdAt / 1000).formatted()).font(.caption).foregroundStyle(RT.muted)
                    }.padding(.vertical, 8)
                }
                if hasMore { Button("加载更多") { Task { await load(reset: false) } }.disabled(loading) }
                Button("刷新记录") { Task { await load() } }.disabled(loading)
            }
        }.navigationTitle("起跑记录").navigationBarTitleDisplayMode(.inline).rtErrorAlert($error).task { await load() }
    }
    private func load(reset: Bool = true) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { let data: SoloRecords = try await api.request("/api/starts?offset=\(reset ? 0 : records.count)"); records = reset ? data.records : records + data.records; hasMore = data.hasMore }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
