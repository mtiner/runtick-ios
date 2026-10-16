import SwiftUI

/// Shown once per process launch, never when merely returning from the background.
struct LaunchContainer: View {
    @Bindable var model: AppModel
    @State private var launching = true
    @AppStorage("onboarded") private var onboarded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            RootView(model: model, guideIsVisible: !launching).allowsHitTesting(!launching).accessibilityHidden(launching)
            if launching { BrandLaunchView().transition(.opacity).zIndex(1) }
        }
        .task {
            #if DEBUG
            // Deterministic simulator capture, with no network or account data.
            if ProcessInfo.processInfo.arguments.contains("--brand-preview") { return }
            #endif
            do { try await Task.sleep(for: .milliseconds(1300)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { launching = false }
        }
        .task(id: onboarded) {
            // First-launch networking belongs to the visible preparation page.
            if onboarded { await model.restore() }
        }
    }
}

struct BrandLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        ZStack {
            RTBackdrop()
            VStack(spacing: 0) {
                Image("BrandIcon").resizable().interpolation(.high).scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: RT.deep.opacity(0.16), radius: 24, y: 12)
                    .accessibilityHidden(true)
                VStack(spacing: 12) {
                    RTWordmark().fill(RT.ink, style: FillStyle(eoFill: true)).frame(width: 150, height: 33)
                    RTWordmark(chinese: true).fill(RT.ink, style: FillStyle(eoFill: true)).frame(width: 60, height: 26)
                }.padding(.top, 30).accessibilityElement(children: .ignore).accessibilityLabel("RunTick 燃刻")
                Text("为每一次认真训练而生")
                    .font(.system(size: 13, weight: .regular)).tracking(1.5)
                    .foregroundStyle(Color(red: 0.58, green: 0.65, blue: 0.62))
                    .multilineTextAlignment(.center).padding(.top, 28)
            }
            .padding(32).frame(maxWidth: 460)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.97)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .light)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) { appeared = true } }
    }
}
