import SwiftUI
import AVFoundation
import MediaPlayer

@MainActor @Observable final class AudioReadiness {
    var volume: Float = 0
    var route = "正在检测"
    var speaker = false
    var error = ""
    private var observation: NSKeyValueObservation?
    var maximumVolume: Bool { volume >= 0.999 }
    func refresh() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback intentionally plays even while the device's silent switch is on.
            if session.category != .playback { try session.setCategory(.playback, mode: .default, options: []) }
            try session.setActive(true)
            volume = session.outputVolume
            speaker = session.currentRoute.outputs.allSatisfy { $0.portType == .builtInSpeaker } && !session.currentRoute.outputs.isEmpty
            route = session.currentRoute.outputs.map(\.portName).joined(separator: "、")
            if observation == nil {
                observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
                    let value = session.outputVolume
                    Task { @MainActor in self?.volume = value }
                }
            }
        } catch { self.error = "无法准备发令声音，请稍后重试或重新打开 App。" }
    }
    func stop() { observation?.invalidate(); observation = nil }
}
struct SystemVolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
struct AudioPreparationCard: View {
    @State private var audio = AudioReadiness()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        RTCard("声音准备") {
            HStack {
                Label("媒体音量", systemImage: audio.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                Spacer()
                Text("\(Int((audio.volume * 100).rounded()))%").monospacedDigit().fontWeight(.semibold)
            }
            SystemVolumeControl().frame(height: 34).accessibilityLabel("媒体音量，发令前请调至最大")
            if !audio.maximumVolume { RTNotice(text: audio.volume == 0 ? "当前媒体音量为零，请调至最大，以免听不到枪声。" : "请将媒体音量调至最大，确保清楚听到发令。") }
            HStack { Text("声音输出"); Spacer(); Text(audio.route).foregroundStyle(RT.muted).multilineTextAlignment(.trailing) }.font(.subheadline)
            if !audio.speaker { RTNotice(text: "请断开耳机、蓝牙或外接音响，使用本机扬声器发令，避免输出延迟。") }
            Label("发令可在静音模式下播放", systemImage: "bell.slash").font(.subheadline)
            Text("App 使用媒体播放通道，不受铃声静音开关影响。请用上方滑块或音量键调整媒体音量。").font(.caption).foregroundStyle(RT.muted).lineSpacing(4)
        }
        .onAppear { audio.refresh() }.onDisappear { audio.stop() }
        .onChange(of: phase) { _, phase in if phase == .active { audio.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in audio.refresh() }
        .rtErrorAlert($audio.error)
    }
}
