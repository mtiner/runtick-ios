import SwiftUI

/// Keep a dismissed error in the model so identical polling failures do not reopen the alert.
private struct NativeErrorAlert: ViewModifier {
    @Binding var message: String
    var enabled: Bool
    @State private var showing = false
    @State private var presented = ""
    @State private var lastMessage = ""
    func body(content: Content) -> some View {
        content
            .onChange(of: message, initial: true) { _, _ in presentIfNeeded() }
            .onChange(of: enabled) { _, value in if !value { showing = false } else { presentIfNeeded() } }
            .onChange(of: showing) { _, value in if !value { presentIfNeeded() } }
            .alert(title, isPresented: $showing) { Button("好", role: .cancel) {} } message: { Text(presented) }
    }
    private var title: String { presented.contains("网络") || presented.contains("连接") ? "连接未成功" : "操作未完成" }
    private func presentIfNeeded() {
        if message.isEmpty { lastMessage = ""; return }
        guard enabled, !showing, message != lastMessage else { return }
        presented = message; lastMessage = message; showing = true
    }
}
extension View {
    func rtErrorAlert(_ message: Binding<String>, enabled: Bool = true) -> some View {
        modifier(NativeErrorAlert(message: message, enabled: enabled))
    }
}
