import SwiftUI

@main struct RunTickApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--solo-preview") { NavigationStack { SoloStartView(api: APIClient(baseURL: AppConfiguration.serverURL), user: User(id: 1, loginId: "RunTick")) } }
                else if ProcessInfo.processInfo.arguments.contains("--about-preview") { NavigationStack { AboutView() } }
                else if ProcessInfo.processInfo.arguments.contains("--starter-preview") { TimingPreviewView(role: .start) }
                else if ProcessInfo.processInfo.arguments.contains("--finish-preview") || ProcessInfo.processInfo.arguments.contains("--settings-preview") { TimingPreviewView(role: .finish) }
                else { LaunchContainer(model: model) }
                #else
                LaunchContainer(model: model)
                #endif
            }
                .task { _ = try? await AppTimeSync.synchronize { _ in } }
                .tint(Color(red: 0.12, green: 0.62, blue: 0.58))
                .onChange(of: phase) { _, value in
                    UIApplication.shared.isIdleTimerDisabled = value == .active && model.room != nil
                    if value == .active { model.room?.resume(); model.scheduleSync() } else { model.room?.interrupt() }
                }
                .onChange(of: model.room != nil) { _, active in UIApplication.shared.isIdleTimerDisabled = active }
        }
    }
}
