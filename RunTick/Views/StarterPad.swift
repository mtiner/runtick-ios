import SwiftUI

struct StarterPad: View {
    @Bindable var model: RoomModel
    let leave: () -> Void
    var body: some View {
        ZStack {
            RTBackdrop()
            VStack(spacing: 28) {
                HStack { Text("\(model.user.loginId) · 房间 \(model.code)"); Spacer() }
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    VStack(spacing: 22) {
                        Text(model.cue.isEmpty ? (model.race?.startAt == nil ? "准备发令" : "计时中") : model.cue)
                            .font(.system(size: 48, weight: .bold)).multilineTextAlignment(.center)
                            .contentTransition(.opacity)
                        if let deadline = model.cueDeadline {
                            Text("\(max(0, Int(ceil((deadline - MonotonicClock.now()) / 1000))))")
                                .font(.system(size: 112, weight: .semibold, design: .rounded))
                                .monospacedDigit().contentTransition(.numericText(countsDown: true))
                                .accessibilityLabel("倒计时")
                        } else {
                            Image(systemName: model.race?.startAt == nil ? "speaker.wave.3.fill" : "figure.run")
                                .font(.system(size: 76)).padding(.vertical, 16)
                        }
                    }.frame(maxWidth: .infinity)
                }
                Text(model.race?.startAt == nil ? "跟随口令，准备出发" : "枪声已发出 · 等待冲线")
                    .foregroundStyle(RT.muted)
                if !model.firing && model.race?.startAt == nil && model.pending == nil {
                    Button("重新发令") { Task { await model.fire() } }
                        .buttonStyle(RTButtonStyle()).disabled(model.syncing)
                }
                Spacer()
                Text("保持 App 在前台，使用扬声器播放")
                    .font(.footnote).foregroundStyle(RT.muted)
            }.padding(28).frame(maxWidth: 650)
            VStack {
                HStack { Spacer(); Button("返回房间", action: leave).buttonStyle(.glass) }
                Spacer()
            }.padding()
        }.foregroundStyle(RT.ink)
            .task(id: "\(model.race?.id ?? ""):\(model.race?.starterSettings != nil)") {
                // Preview renders must never play audio or send timing events.
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--starter-preview") { return }
                #endif
                await model.autoFire()
            }
            .rtErrorAlert($model.error)
    }
}
