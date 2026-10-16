import SwiftUI

@main struct RunTickApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--starter-preview") { TimingPreviewView(role: .start) }
                else if ProcessInfo.processInfo.arguments.contains("--finish-preview") { TimingPreviewView(role: .finish) }
                else { LaunchContainer(model: model) }
                #else
                LaunchContainer(model: model)
                #endif
            }
                .tint(Color(red: 0.12, green: 0.62, blue: 0.58))
                .onChange(of: phase) { _, value in
                    UIApplication.shared.isIdleTimerDisabled = value == .active && model.room != nil
                    if value == .active { model.room?.resume() } else { model.room?.interrupt() }
                }
                .onChange(of: model.room != nil) { _, active in UIApplication.shared.isIdleTimerDisabled = active }
        }
    }
}
