import SwiftUI
import UIKit

struct RoomView: View {
    @Bindable var model: RoomModel
    let leave: () -> Void
    @State private var soundCheck = false
    @State private var distance = "100"
    @State private var testAudio = StarterAudio()
    var finishVisible: Bool { model.raceRole == .finish && model.race?.active == true && model.race?.finishAt == nil && model.clock != nil && model.pending == nil }
    var body: some View {
        Form {
            Section("房间 \(model.code)") {
                Label(model.connected ? (model.ready ? "两端已就绪" : "等待另一台手机") : "连接中，自动重连…", systemImage: model.connected ? "wifi" : "wifi.slash")
                if model.syncing { ProgressView("HTTP 校时 \(model.progress)/20", value: Double(model.progress), total: 20) }
                else if let clock = model.clock { Text("20 次校时 · 平均 RTT \(clock.averageRttMs, specifier: "%.1f") ms · 估算 ±\(clock.uncertaintyMs, specifier: "%.0f") ms") }
                Button("重新校准时间") { Task { await model.calibrate() } }.disabled(model.syncing || model.firing || model.pressed)
            }
            if model.race?.active != true && model.race?.status != "completed" {
                Section("我的角色") { ForEach(DeviceRole.allCases, id: \.self) { role in Button { Task { await model.pick(role) } } label: { HStack { Text(role.title); Spacer(); if model.role == role { Image(systemName: "checkmark") } } }.disabled(!model.connected || model.busy) } }
                Section("房间成员（\(model.members.count)/2）") { ForEach(model.members) { member in HStack { Text(member.loginId); Spacer(); Text("\(member.deviceRole?.title ?? "同步中") · \(member.online == true ? "在线" : "离线")").foregroundStyle(.secondary) } } }
            }
            if let race = model.race { raceSection(race) }
            if model.role == .start && model.race?.active != true && model.race?.status != "completed" {
                Button("开始记录") { soundCheck = true }.disabled(!model.ready || !model.connected || model.clock == nil || model.syncing || model.busy)
            }
            if let pending = model.pending { Section("待提交时间戳") { Text("轮次 \(pending.raceId) · \(pending.event.kind.title)\n原始时间戳已保留，联网后自动重试"); Button("重试提交") { Task { await model.submit() } }.disabled(model.submitting) } }
            if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
            NavigationLink("历史成绩") { HistoryView(api: model.api, user: model.user, room: model.code) }
            Button("返回房间入口", action: leave)
        }
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $soundCheck) {
            NavigationStack { Form {
                Section("开始前确认声音") { Text("调高音量，使用手机扬声器；确认终点已进入触控区后再发令。")
                    Button("试听原声") { Task { try? await testAudio.play(settings: StageDelay.defaults, cue: { _ in }, gun: { _, _ in }) } }
                    Button("已确认声音，开始记录") { testAudio.stop(); soundCheck = false; Task { await model.raceAction() } }
                }
                Button("返回准备") { soundCheck = false }
            }.navigationTitle("声音检查") }.presentationDetents([.medium]).onDisappear { testAudio.stop() }
        }
        .fullScreenCover(isPresented: Binding(get: { finishVisible }, set: { _ in })) {
            FinishPad(model: model, leave: leave).interactiveDismissDisabled()
        }
    }
    @ViewBuilder func raceSection(_ race: Race) -> some View {
        Section("本轮 · \(race.status)") {
            if race.status == "completed" {
                Text(String(format: "%.3f 秒", (race.elapsedMs ?? 0) / 1000)).font(.system(.largeTitle, design: .rounded).monospacedDigit())
                Text("服务端已保存 · 估算误差 ±\(race.uncertaintyMs ?? 0, specifier: "%.0f") ms（不含人工反应）").font(.footnote)
                if let saved = race.savedResult {
                    Label("已保存 \(saved.distance) 米\(saved.isPb ? " · PB！" : "")", systemImage: saved.isPb ? "trophy.fill" : "checkmark.circle")
                        .foregroundStyle(saved.isPb ? .orange : .teal)
                        .sensoryFeedback(.success, trigger: saved.isPb)
                    if let improvement = saved.pbImprovementMs { Text("比原 PB 快 \(improvement / 1000, specifier: "%.2f") 秒") }
                    Button("下一组") { Task { await model.raceAction("next") } }.disabled(model.busy)
                } else if model.raceRole == .finish {
                    Text("成绩保存至起点运动员名下")
                    TextField("距离（米）", text: $distance).keyboardType(.numberPad)
                    ScrollView(.horizontal) { HStack { ForEach([20,30,40,50,60,80,100,120,150,200,300,400,800,1500], id: \.self) { value in Button("\(value)") { distance = String(value) }.buttonStyle(.bordered) } } }
                    Button("保存成绩") { Task { await model.save(distance: Int(distance) ?? 0) } }.disabled(model.busy)
                } else { Text("等待终点记录员填写距离并保存") }
            } else if race.active {
                if model.raceRole == .start {
                    Text(model.cue.isEmpty ? "等待发令" : model.cue).font(.title2)
                    ForEach(0..<3, id: \.self) { i in
                        VStack(alignment: .leading) {
                            Text(["点击 → 各就位", "各就位结束 → 预备", "预备结束 → 枪声"][i]).font(.headline)
                            Toggle("随机等待", isOn: $model.stages[i].random)
                            HStack { Text("等待 / 下限（秒）"); TextField("秒", value: $model.stages[i].min, format: .number).keyboardType(.decimalPad) }
                            if model.stages[i].random { HStack { Text("上限（秒）"); TextField("秒", value: $model.stages[i].max, format: .number).keyboardType(.decimalPad) } }
                        }.disabled(model.firing || race.startAt != nil || model.pending != nil)
                    }
                    Button("开始发令") { Task { await model.fire() } }.disabled(model.clock == nil || model.syncing || model.firing || race.startAt != nil || model.pending != nil || !model.stages.allSatisfy(\.valid))
                } else { Text(race.finishAt == nil ? "校时完成后进入终点触控区" : "终点时间已保存，等待枪声时间戳") }
            } else if race.status == "invalid" { Text("终点早于枪声或用时超过一小时，本轮无效，请重新开始。") }
        }
    }
}

struct FinishPad: View {
    @Bindable var model: RoomModel
    let leave: () -> Void
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ZStack {
            (model.pressed ? Color(red: 0.72, green: 0.93, blue: 0.47) : Color(red: 0.40, green: 0.86, blue: 0.83)).ignoresSafeArea()
            VStack(spacing: 30) {
                HStack { Text("\(model.user.loginId) · 房间 \(model.code)"); Spacer(); Button("返回", action: { model.cancelPress(); leave() }) }.padding()
                Spacer()
                Image(systemName: "hand.point.up.fill").font(.system(size: 70))
                Text(model.pressed ? "冲线时松手" : "按住屏幕，等待冲线").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text(model.race?.startAt == nil ? "可以提前按住 · 等待枪声" : "计时中 · 松开记录")
                Text("取消触控不会记录成绩").font(.footnote)
                Spacer()
                if model.clock?.fresh != true { Button("重新校时") { Task { await model.calibrate() } } }
                Text(model.error).foregroundStyle(.red).padding()
            }.allowsHitTesting(false)
            TouchCapture(onDown: { model.press() }, onUp: { model.release(at: $0) }, onCancel: { model.cancelPress() }).padding(.top, 100)
            VStack { HStack { Spacer(); Button("返回房间", action: { model.cancelPress(); leave() }).buttonStyle(.glass) }; Spacer(); if model.clock?.fresh != true { Button("重新校时") { Task { await model.calibrate() } }.buttonStyle(.glass) } }.padding()
        }.foregroundStyle(Color(red: 0.07, green: 0.24, blue: 0.23))
            .onChange(of: phase) { _, phase in if phase != .active { model.cancelPress() } }
            .onDisappear { model.cancelPress() }
    }
}
struct TouchCapture: UIViewRepresentable {
    var onDown: () -> Void; var onUp: (Double) -> Void; var onCancel: () -> Void
    func makeUIView(context: Context) -> PadUIView { let view = PadUIView(); updateUIView(view, context: context); return view }
    func updateUIView(_ view: PadUIView, context: Context) { view.down = onDown; view.up = onUp; view.cancel = onCancel }
    final class PadUIView: UIView {
        var down: (() -> Void)?; var up: ((Double) -> Void)?; var cancel: (() -> Void)?
        override init(frame: CGRect) { super.init(frame: frame); isMultipleTouchEnabled = false; isAccessibilityElement = true; accessibilityLabel = "终点触控区，按住后冲线时松手"; accessibilityTraits = [.allowsDirectInteraction] }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { down?() }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { let at = MonotonicClock.now(); up?(at) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancel?() }
    }
}
