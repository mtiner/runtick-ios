import SwiftUI
import UIKit

struct RoomView: View {
    @Bindable var model: RoomModel
    var onEditAvatar: (() -> Void)? = nil
    let leave: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var roleHighlight
    @State private var soundCheck = false
    @State private var recording = false
    @State private var confirmExit = false
    @State private var distance = "100"
    var recordingVisible: Bool { model.race?.active == true && (model.raceRole == .start || (model.raceRole == .finish && model.race?.finishAt == nil && model.pending == nil)) }
    var body: some View {
        RTPage {
            RTBrand(onExit: requestExit, exiting: model.busy).rtEntrance()
            TimeSyncStatus(model: model)
            RTHero(badge: "房间 \(model.code)", title: model.race?.status == "completed" ? "本次成绩" : model.race?.active == true ? (model.raceRole == .start ? "起跑发令" : "终点记录") : "房间准备", subtitle: "准备好，就出发。").rtEntrance(0.04)
            if model.race?.active != true {
            RTCard("房间 \(model.code)") {
                Label(model.connected ? (model.ready ? "两端已就绪" : "等待另一台手机") : "连接中，自动重连…", systemImage: model.connected ? "network" : "network.slash")
                if model.syncing { ProgressView("NTP 校时 \(model.progress)/\(model.syncTarget)", value: Double(model.progress), total: Double(model.syncTarget)) }
                else if let clock = model.clock { Text("NTP \(clock.server) · \(clock.validSamples) 样本 · RTT \(clock.averageRttMs, specifier: "%.1f") ms · 估算 ±\(clock.estimatedUncertaintyMs, specifier: "%.0f") ms").font(.footnote).foregroundStyle(RT.muted) }
                if !model.syncDetail.isEmpty { Text(model.syncDetail).font(.footnote).foregroundStyle(RT.muted).accessibilityIdentifier("ntp.detail") }
                Button("重新校准时间") { Task { await model.calibrate() } }.disabled(model.syncing || model.firing || model.pressed)
            }
            }
            if model.race?.active != true && model.race?.status != "completed" {
                RTCard("我的角色") {
                    HStack(spacing: 0) { ForEach(DeviceRole.allCases, id: \.self) { role in
                        Button { Task { await model.pick(role) } } label: {
                            HStack(spacing: 8) {
                                Image(systemName: role == .start ? "figure.run" : "flag.checkered")
                                Text(role.title)
                            }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background {
                                    if model.role == role {
                                        Capsule().fill(.white).shadow(color: RT.ink.opacity(0.07), radius: 5, y: 2)
                                            .matchedGeometryEffect(id: "selected-role", in: roleHighlight)
                                    }
                                }.contentShape(Capsule())
                        }.buttonStyle(.plain).disabled(!model.connected || model.busy || soundCheck)
                            .accessibilityValue(model.role == role ? "已选中" : "未选中")
                    } }.padding(4).background(RT.ink.opacity(0.055), in: Capsule())
                        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: model.role)
                }.rtEntrance(0.08)
                RTCard("房间成员（\(model.members.count)/2）") { ForEach(model.members) { member in HStack {
                    if member.loginId == model.user.loginId, let onEditAvatar {
                        Button(action:onEditAvatar) { UserAvatarView(filename:member.avatar,name:member.loginId,size:36) }.buttonStyle(.plain).accessibilityLabel("修改头像")
                    } else { UserAvatarView(filename:member.avatar,name:member.loginId,size:36) }
                    Text(member.loginId); Spacer(); Text("\(model.displayedRole(for: member)?.title ?? "同步中") · \(member.online == true ? "在线" : "离线")").foregroundStyle(.secondary) } } }
            }
            if let race = model.race { raceRTCard(race).id(race.id).rtEntrance(0.08) }
            if model.role != nil && model.race?.active != true && model.race?.status != "completed" {
                Button("开始记录") { soundCheck = true }.buttonStyle(RTButtonStyle()).disabled(!model.ready || !model.connected || model.clock?.fresh != true || model.syncing || model.busy)
            }
            if let pending = model.pending { RTCard("计时记录待同步") { Text("\(pending.event.kind == .start ? "起点" : "终点")计时已保存在此设备上，联网后将自动重试同步。"); Button("重新同步") { Task { await model.submit() } }.disabled(model.submitting) } }
            NavigationLink("历史成绩") { HistoryView(api: model.api, user: model.user, room: model.code, onEditAvatar:onEditAvatar) }
            Button("退出房间", systemImage: "rectangle.portrait.and.arrow.right", action: requestExit)
        }
        .confirmationDialog("退出房间？", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("仍然退出", role: .destructive, action: leave)
            Button("继续留在房间", role: .cancel) {}
        } message: { Text("本轮仍在记录或有计时数据尚未同步。退出可能影响本轮成绩，建议完成并同步后再退出。") }
        .rtErrorAlert($model.error, enabled: !recording && !soundCheck)
        .navigationBarBackButtonHidden()
        .onAppear {
            recording = recordingVisible
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--settings-preview") { soundCheck = true }
            #endif
        }
        .onChange(of: recordingVisible) { _, visible in
            if visible && soundCheck { soundCheck = false }
            else { recording = visible }
        }
        .sheet(isPresented: $soundCheck, onDismiss: { recording = recordingVisible }) {
            NavigationStack {
                RTPage {
                    Text("房间 \(model.code) · 确认后双端进入记录页面").font(.subheadline).foregroundStyle(RT.muted)
                    RTCard("发令时间") {
                        Toggle("检测起跑反应时", isOn: Binding(get: { model.stages[0].reactionEnabled == true }, set: { model.stages[0].reactionEnabled = $0 }))
                        Text("有起跑器并固定手机后开启；三点式起跑可关闭，不影响发令或跑步成绩。").font(.footnote).foregroundStyle(RT.muted)
                        Toggle("播放各就位口令", isOn: Binding(get: { model.stages[0].enabled != false }, set: { model.stages[0].enabled = $0 }))
                        Text("将起点手机贴靠或固定在起跑器上，并保持稳定，以检测起跑反应。结果为设备运动估算。").font(.footnote).foregroundStyle(RT.muted)
                        ForEach(0..<3, id: \.self) { i in
                            if i != 0 || model.stages[0].enabled != false {
                                StageDelayControl(title: ["开始 → 各就位", model.stages[0].enabled == false ? "开始 → 预备" : "各就位结束 → 预备", "预备结束 → 枪声"][i], stage: $model.stages[i])
                            }
                        }
                    }.disabled(model.busy)
                    if model.role == .start { AudioPreparationCard() }
                    else { Text("请确认起点手机的媒体音量已调至最大，并使用扬声器播放发令声音。").font(.footnote).foregroundStyle(RT.muted) }
                }.safeAreaInset(edge: .bottom) {
                    VStack(spacing: 12) {
                        Button(model.busy ? "正在开始…" : "确认并开始记录") {
                            Task { await model.beginRecording() }
                        }.buttonStyle(RTButtonStyle()).disabled(model.busy || !model.stages.allSatisfy(\.valid))
                        Button("返回准备") { soundCheck = false }.font(.subheadline).disabled(model.busy)
                    }.padding(.horizontal, 24).padding(.vertical, 14).background(.ultraThinMaterial)
                }.navigationTitle("发令设置").navigationBarTitleDisplayMode(.inline)
                    .rtErrorAlert($model.error)
            }.presentationDetents([.large]).interactiveDismissDisabled(model.busy)
        }
        .fullScreenCover(isPresented: $recording) {
            Group {
                if model.raceRole == .start { StarterPad(model: model, leave: closeRecording) }
                else { FinishPad(model: model, leave: closeRecording) }
            }.interactiveDismissDisabled()
        }
    }
    private func requestExit() {
        if model.race?.active == true || model.pending != nil { confirmExit = true } else { leave() }
    }
    private func closeRecording() { model.interrupt(); recording = false }
    private func resultNumber(_ race: Race, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(format: "%.3f", (race.elapsedMs ?? 0) / 1000))
                .font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            Text("秒").font(.headline).foregroundStyle(RT.muted)
        }
    }
    @ViewBuilder func raceRTCard(_ race: Race) -> some View {
        RTCard("本轮 · " + (["ready": "准备中", "running": "计时中", "completed": "已完成", "invalid": "无效", "cancelled": "已取消"][race.status] ?? race.status)) {
            if race.status == "completed" {
                VStack(spacing: 10) {
                    RTChip(text: "计时完成", lemon: true)
                    ViewThatFits { resultNumber(race, size: 62); resultNumber(race, size: 42) }
                }.frame(maxWidth: .infinity).padding(.vertical, 20).rtEntrance()

                if race.reactionStatus == "false_start" { RTChip(text: "抢跑", lemon: true) }
                Text(ReactionResult.text(race.reactionMs, race.reactionStatus) + " · 手机运动检测估算").font(.subheadline)
                Text("本轮计时完成 · 估算误差 ±\(race.uncertaintyMs ?? 0, specifier: "%.0f") ms（不含人工反应）").font(.footnote)
                if let saved = race.savedResult {
                    if saved.isPb { RTPBCelebration(improvement: saved.pbImprovementMs) }
                    Label("已保存 \(saved.distance) 米\(saved.isPb ? " · PB！" : "")", systemImage: saved.isPb ? "trophy.fill" : "checkmark.circle")
                        .foregroundStyle(saved.isPb ? .orange : .teal)
                        .sensoryFeedback(.success, trigger: saved.isPb)
                    if let improvement = saved.pbImprovementMs { Text("比原 PB 快 \(improvement / 1000, specifier: "%.2f") 秒") }
                    Button("下一组") { Task { await model.raceAction("next") } }.buttonStyle(RTButtonStyle()).disabled(model.busy)
                } else if model.raceRole == .finish {
                    Text("成绩保存至起点运动员名下")
                    TextField("距离（米）", text: $distance).keyboardType(.numberPad).rtField()
                    ScrollView(.horizontal) { HStack { ForEach([20,30,40,50,60,80,100,120,150,200,300,400,800,1500], id: \.self) { value in Button("\(value)") { distance = String(value) }.buttonStyle(.bordered) } } }
                    Button("保存成绩") { Task { await model.save(distance: Int(distance) ?? 0) } }.buttonStyle(RTButtonStyle()).disabled(model.busy)
                } else { Text("等待终点记录员填写距离并保存") }
            } else if race.active {
                if model.clock == nil {
                    if model.syncing { ProgressView("正在校时…") }
                    else { Button("重新校时") { Task { await model.calibrate() } } }
                }
                if model.raceRole == .start {
                    Text(model.cue.isEmpty ? "等待发令" : model.cue).font(.title2)
                    Text("发令设置已确认，正在全屏记录。")
                    Button("进入记录页") { recording = true }.buttonStyle(RTButtonStyle()).accessibilityIdentifier("room.resumeRecording")
                } else {
                    Text(race.finishAt == nil ? "按住屏幕，冲线时松手" : "已记录冲线，等待起点同步")
                    if recordingVisible { Button("进入记录页") { recording = true }.buttonStyle(RTButtonStyle()).accessibilityIdentifier("room.resumeRecording") }
                }
            } else if race.status == "invalid" { Text("终点早于枪声或用时超过一小时，本轮无效，请重新开始。") }
        }
    }
}

struct FinishPad: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: RoomModel
    let leave: () -> Void
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ZStack {
            (model.pressed ? Color(red: 0.72, green: 0.93, blue: 0.47) : Color(red: 0.40, green: 0.86, blue: 0.83)).ignoresSafeArea()
            GeometryReader { geometry in
            VStack(spacing: min(24, geometry.size.height * 0.035)) {
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 1).frame(width: min(180, geometry.size.height * 0.25), height: min(180, geometry.size.height * 0.25))
                    Circle().stroke(.white.opacity(0.45), lineWidth: 2).frame(width: model.pressed ? 130 : 110, height: model.pressed ? 130 : 110)
                    Image(systemName: "hand.point.up.fill").font(.system(size: 64, weight: .light)).symbolEffect(.pulse, options: .repeating, isActive: model.pressed && !reduceMotion)
                }.animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.65), value: model.pressed)
                Text(model.pressed ? "冲线时松手" : "按住屏幕，等待冲线").font(.system(size: min(32, geometry.size.height * 0.055), weight: .bold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.65)
                Text(model.race?.startAt == nil ? "可以提前按住 · 等待枪声" : "计时中 · 松开记录")
                Text("取消触控不会记录成绩").font(.footnote)
                Spacer()
            }.padding(.bottom, 30).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }.allowsHitTesting(false)
            TouchCapture(onDown: { model.press() }, onUp: { model.release(at: $0) }, onCancel: { model.cancelPress() }).padding(.top, 100)
            VStack { Spacer(); TimelineView(.periodic(from: .now, by: 1)) { _ in
                if !model.hasRecordingClock { Button(model.syncing ? "正在校时…" : "重新校时") { Task { await model.calibrate() } }.buttonStyle(.glass).disabled(model.syncing) }
            } }.padding()
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.pressed).sensoryFeedback(.impact(weight: .light), trigger: model.pressed).foregroundStyle(Color(red: 0.07, green: 0.24, blue: 0.23))
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 2) { RecordingHeader(name: model.user.loginId, code: model.code) { model.cancelPress(); leave() }; TimeSyncStatus(model:model) }
            }
            .onChange(of: phase) { _, phase in if phase != .active { model.cancelPress() } }
            .onDisappear { model.cancelPress() }
            .rtErrorAlert($model.error)
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
        private var tracking = false
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { tracking = true; down?() }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let touch = touches.first, !bounds.contains(touch.location(in: self)) { tracking = false; cancel?() }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard tracking, let touch = touches.first, bounds.contains(touch.location(in: self)) else { tracking = false; cancel?(); return }
            tracking = false; up?(MonotonicClock.fromUptime(touch.timestamp))
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { tracking = false; cancel?() }
    }
}

struct TimeSyncStatus: View {
    @Bindable var model: RoomModel
    var body: some View {
        TimelineView(.periodic(from:.now,by:1)) { _ in Text(model.syncSummary).font(.caption).foregroundStyle(RT.muted).accessibilityLabel(model.syncSummary) }
    }
}
