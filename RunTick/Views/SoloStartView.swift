import SwiftUI

@MainActor @Observable final class SoloStartModel {
    let api: APIClient; let user: User
    var stages = StageDelay.defaults
    var running = false; var cue = ""; var deadline: Double?; var error = ""
    var result: ReactionResult?; var volumeWarning = false
    private let audio = StarterAudio(); private let motion = ReactionMotion()
    private var task: Task<Void, Never>?
    init(api: APIClient, user: User) {
        self.api = api; self.user = user
        if let bytes = UserDefaults.standard.data(forKey: "starter"), let saved = try? JSONDecoder().decode([StageDelay].self, from: bytes), saved.count == 3, saved.allSatisfy(\.valid) { stages = saved }
    }
    func start(allowReducedVolume: Bool = false) {
        guard !running, stages.count == 3, stages.allSatisfy(\.valid) else { return }
        do { if !allowReducedVolume, try audio.needsVolumeConfirmation() { volumeWarning = true; return } }
        catch { self.error = error.localizedDescription; return }
        running = true; result = nil; error = ""; cue = "请保持手机与起跑器稳定…"
        UserDefaults.standard.set(try? JSONEncoder().encode(stages), forKey: "starter")
        let id = UUID().uuidString, saved = stages
        task = Task {
            do {
                try await motion.prepare(enabled: saved[0].reactionEnabled == true); try Task.checkCancellation()
                try await audio.play(settings: saved, cue: { self.cue = $0; self.deadline = $1 }, gun: { at, _ in
                    let firedAt = Date().timeIntervalSince1970 * 1000
                    self.motion.gun(at: at) { value in
                        self.result = value
                        Task {
                            do {
                                let settings = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved))
                                try await TrainingSync.send(api: self.api, userId: self.user.id, path: "/api/starts", body: ["id": id, "firedAt": firedAt, "settings": settings, "reactionMs": value.reactionMs as Any? ?? NSNull(), "reactionStatus": value.reactionStatus], id: id)
                            } catch { self.error = "记录已保留在本机，联网后可重试：" + error.localizedDescription }
                        }
                    }
                })
                deadline = nil
            } catch is CancellationError {} catch { self.error = error.localizedDescription; stop() }
        }
    }
    func stop() { task?.cancel(); motion.end(); audio.stop(); running = false; deadline = nil; volumeWarning = false }
}
struct SoloStartView: View {
    @State private var model: SoloStartModel
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
                    if let result = model.result { Text(result.text).font(.title2).frame(maxWidth: .infinity) }
                    Button("结束本轮") { model.stop() }
                }
            } else {
                RTCard("发令设置") {
                    Toggle("检测起跑反应时", isOn: Binding(get: { model.stages[0].reactionEnabled == true }, set: { model.stages[0].reactionEnabled = $0 }))
                        Text("有起跑器并固定手机后开启；三点式起跑可关闭，不影响发令或跑步成绩。").font(.footnote).foregroundStyle(RT.muted)
                        Toggle("播放各就位口令", isOn: Binding(get: { model.stages[0].enabled != false }, set: { model.stages[0].enabled = $0 }))
                    ForEach(0..<3, id: \.self) { i in
                        if i != 0 || model.stages[0].enabled != false {
                            StageDelayControl(title: ["开始 → 各就位", model.stages[0].enabled == false ? "开始 → 预备" : "各就位结束 → 预备", "预备结束 → 枪声"][i], stage: $model.stages[i])
                        }
                    }
                }
                AudioPreparationCard()
                Text("将手机贴靠或固定在起跑器上，保持稳定。反应时为手机运动检测估算，非专业起跑器计时。保持 App 在前台；后台切换会中断检测。").font(.footnote).foregroundStyle(RT.muted)
                Button("确认设置，开始发令") { model.start() }.buttonStyle(RTButtonStyle())
            }
            NavigationLink("单人起跑记录") { SoloHistoryView(api: model.api) }
            Button("重试同步本机记录") { Task { await TrainingSync.retry(api: model.api, userId: model.user.id) } }
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
        catch { self.error = error.localizedDescription }
    }
}
