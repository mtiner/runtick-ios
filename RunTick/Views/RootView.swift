import SwiftUI
import CoreMotion

struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage("onboarded") private var onboarded = false
    @State private var login = ""
    @State private var password = ""
    @State private var code = ""
    @State private var history = false
    var body: some View {
        NavigationStack {
            Group {
                if !onboarded { GuideView { onboarded = true } }
                else if model.user == nil { loginView }
                else if let room = model.room { RoomView(model: room, leave: { Task { await model.perform { try await model.leave() } } }) }
                else { lobby }
            }
            .navigationTitle("RunTick 燃刻")
            .overlay { if model.loading { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .safeAreaInset(edge: .bottom) { if !model.error.isEmpty { Text(model.error).font(.footnote).foregroundStyle(.red).padding().background(.regularMaterial).accessibilityAddTraits(.updatesFrequently) } }
        }
    }
    var loginView: some View {
        Form {
            Section("连接服务") { TextField("后端 HTTPS 根地址", text: $model.serverAddress).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled() }
            Section("登录，开始计时") {
                Text("首次使用的 ID 将自动创建账号，请记住 ID 和密码。")
                TextField("用户 ID", text: $login).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("密码", text: $password).textContentType(.password).keyboardType(.numberPad)
                Button("登录") { Task { await model.perform { try await model.login(id: login, password: password); password = "" } } }.disabled(model.loading)
            }
        }
    }
    var lobby: some View {
        Form {
            Section { Text("你好，\(model.user?.loginId ?? "")").font(.headline); Text("两台手机、一个房间。起点发令，终点松手。") }
            Section("创建或加入房间") {
                Button("创建房间", systemImage: "plus.circle") { Task { await model.perform { try await model.enter() } } }.disabled(!model.lobbyReady)
                TextField("4 位房间号", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .onChange(of: code) { _, value in code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4)) }
                Button("加入房间") { Task { await model.perform { try await model.enter(code: code) } } }.disabled(code.count != 4 || !model.lobbyReady)
                Button("重试退出旧房间") { Task { await model.perform { try await model.leave() } } }
            }.disabled(model.loading)
            Section {
                if let api = model.api, let user = model.user { NavigationLink("历史成绩") { HistoryView(api: api, user: user, room: nil) } }
                Button("退出登录", role: .destructive) { Task { await model.logout() } }
            }
        }
    }
}

struct GuideView: View {
    let proceed: () -> Void
    @State private var capabilities = "点击检查设备能力"
    @State private var audio = StarterAudio()
    private let motion = CMMotionManager()
    var body: some View {
        Form {
            Section { Image(systemName: "figure.run").font(.system(size: 60)).foregroundStyle(.teal); Text("两端协同，记录每次突破").font(.title2); Text("起点运动员播放原声发令；终点记录员提前按住屏幕，冲线时松手。人工反应误差不包含在校时误差中。") }
            Section("设备准备") {
                Text(capabilities)
                Button("检查传感器与屏幕常亮") {
                    capabilities = "陀螺仪：\(motion.isGyroAvailable ? "可用" : "不支持")\n加速度计：\(motion.isAccelerometerAvailable ? "可用" : "不支持")\n会话存储：系统 Cookie\n屏幕常亮：进入房间后自动启用"
                }
                Text("计时使用原声枪响与触屏松手，不依赖运动传感器。请使用手机扬声器，避免蓝牙音频延迟。")
                Button("试听发令原声") { Task { do { try await audio.play(settings: [StageDelay(random: false, min: 0, max: 0), StageDelay(random: false, min: 0, max: 0), StageDelay(random: false, min: 0, max: 0)], cue: { capabilities = $0 }, gun: { _, _ in }) } catch { capabilities = error.localizedDescription } } }
            }
            Button("开始使用", action: proceed)
        }.onDisappear { audio.stop() }
    }
}
