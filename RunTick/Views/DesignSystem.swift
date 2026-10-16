import SwiftUI

/// Tokens translated from runtick-app/src/styles/main.css.
enum RT {
    static let aqua = Color(hex: 0x65DDD5), deep = Color(hex: 0x2FBFB5)
    static let ink = Color(hex: 0x173E3B), muted = Color(hex: 0x5F7B77)
    static let lemon = Color(hex: 0xE6F56B), background = Color(hex: 0xF7FBF9)
}
private extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255) }
}
struct RTBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RT.background
                RadialGradient(colors: [RT.aqua.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 350)
                RadialGradient(colors: [RT.lemon.opacity(0.27), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 300)
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }.ignoresSafeArea()
    }
}
struct RTPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .frame(maxWidth: 460).padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 32)
                .frame(maxWidth: .infinity)
        }
        .background { RTBackdrop() }
        .foregroundStyle(RT.ink).tint(RT.deep)
        .environment(\.colorScheme, .light)
        .buttonStyle(RTButtonStyle(secondary: true))
        .scrollDismissesKeyboard(.interactively)
    }
}
struct RTCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title { Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(RT.muted) }
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(RT.ink.opacity(0.035)) }
            .shadow(color: RT.ink.opacity(0.055), radius: 18, x: 0, y: 8)
    }
}
struct RTBrand: View {
    var showHelp = true
    var onExit: (() -> Void)? = nil
    var exiting = false
    @State private var help = false
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
            RTWordmark().fill(RT.ink, style: FillStyle(eoFill: true)).frame(width: 100, height: 22)
            Text("/").foregroundStyle(RT.muted.opacity(0.55))
            RTWordmark(chinese: true).fill(RT.ink, style: FillStyle(eoFill: true)).frame(width: 52, height: 22)
            }.accessibilityElement(children: .ignore).accessibilityLabel("RunTick 燃刻")
            Spacer(minLength: 4)
            if let onExit {
                Button(action: onExit) { Image(systemName: "rectangle.portrait.and.arrow.right").frame(width: 34, height: 34) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).disabled(exiting).accessibilityLabel("退出房间")
            }
            if showHelp {
                Button { help = true } label: { Image(systemName: "questionmark").frame(width: 34, height: 34) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("使用说明")
            }
        }.padding(.bottom, 4)
            .sheet(isPresented: $help) { NavigationStack { HelpView() } }
    }
}
struct RTBrandFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            RTWordmark().fill(RT.muted.opacity(0.45), style: FillStyle(eoFill: true)).frame(width: 73, height: 16)
            Text("/").font(.footnote).foregroundStyle(RT.muted.opacity(0.3))
            RTWordmark(chinese: true).fill(RT.muted.opacity(0.45), style: FillStyle(eoFill: true)).frame(width: 38, height: 16)
        }.frame(maxWidth: .infinity).padding(.top, 22).accessibilityHidden(true)
    }
}
struct RTHero: View {
    let badge: String; let title: String; var subtitle = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            RTChip(text: badge)
            Text(title).font(.system(size: 28, weight: .heavy)).tracking(0.3).multilineTextAlignment(.center).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 14)).foregroundStyle(RT.muted).lineSpacing(5).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
        }.padding(.vertical, 8)
    }
}
struct RTChip: View {
    let text: String; var lemon = false
    var body: some View { Text(text).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 13).padding(.vertical, 7).background(lemon ? RT.lemon : RT.aqua.opacity(0.22), in: Capsule()) }
}
struct RTButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 24).padding(.horizontal, 16).padding(.vertical, 15)
            .foregroundStyle(secondary ? RT.ink : .white)
            .background {
                RoundedRectangle(cornerRadius: 16).fill(secondary ?
                    LinearGradient(colors: [Color(hex: 0xEDF4F2), Color(hex: 0xEDF4F2)], startPoint: .top, endPoint: .bottom) :
                    LinearGradient(colors: [Color(hex: 0x7CE5DD), Color(hex: 0x4FD2C8)], startPoint: .top, endPoint: .bottom))
            }
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(secondary ? RT.ink.opacity(0.10) : Color.white.opacity(0.45)) }
            .shadow(color: secondary ? .clear : RT.aqua.opacity(0.30), radius: 12, y: 6)
            .opacity(enabled ? 1 : 0.42).scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
struct RTFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 16)).padding(16).background(RT.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(RT.ink.opacity(0.09)) }
    }
}
struct RTEntrance: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    func body(content: Content) -> some View {
        content.opacity(visible || reduceMotion ? 1 : 0).offset(y: visible || reduceMotion ? 0 : 14)
            .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85).delay(delay)) { visible = true } }
    }
}
extension View {
    func rtField() -> some View { modifier(RTFieldStyle()) }
    func rtEntrance(_ delay: Double = 0) -> some View { modifier(RTEntrance(delay: delay)) }
}
struct RTNotice: View {
    let text: String; var error = false
    var body: some View { Label(text, systemImage: error ? "exclamationmark.circle" : "checkmark.circle.fill").font(.footnote).lineSpacing(4).foregroundStyle(error ? .red : RT.muted).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(error ? Color.red.opacity(0.06) : RT.aqua.opacity(0.10), in: RoundedRectangle(cornerRadius: 16)) }
}

struct RTPBCelebration: View {
    let improvement: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var playedSound = false
    @State private var pbAudio = PBAudio()
    var body: some View {
        ZStack {
            ForEach(0..<12) { index in
                Capsule().fill(index.isMultiple(of: 2) ? RT.aqua : RT.lemon)
                    .frame(width: 5, height: 12)
                    .offset(y: revealed ? -68 : -20).rotationEffect(.degrees(Double(index) * 30))
                    .opacity(revealed ? 0.85 : 0)
            }.accessibilityHidden(true)
            Image(systemName: "trophy.fill").font(.system(size: 42)).foregroundStyle(RT.ink)
                .frame(width: 92, height: 92).background(RT.lemon, in: Circle())
                .scaleEffect(revealed ? 1 : 0.7)
        }.frame(maxWidth: .infinity).frame(height: 160)
            .overlay(alignment: .bottom) { Text("新的个人最佳！").font(.headline) }
            .onAppear {
                if !playedSound { playedSound = true; pbAudio.play() }
                withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.55)) { revealed = true }
            }
            .onDisappear { pbAudio.stop() }
            .accessibilityLabel("新的个人最佳")
    }
}

struct RTCodeInput: View {
    @Binding var code: String
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                ForEach(0..<4) { index in
                    let digits = Array(code)
                    Text(index < digits.count ? String(digits[index]) : " ")
                        .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                        .frame(maxWidth: .infinity).frame(height: 58)
                        .background(RT.background, in: RoundedRectangle(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(focused && code.count == index ? RT.deep : RT.ink.opacity(0.12), lineWidth: focused && code.count == index ? 2 : 1) }
                }
            }.accessibilityHidden(true)
            TextField("", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                .foregroundStyle(.clear).tint(.clear).focused($focused)
                .accessibilityLabel("4 位房间号").frame(height: 58)
        }.contentShape(Rectangle()).onTapGesture { focused = true }
    }
}
