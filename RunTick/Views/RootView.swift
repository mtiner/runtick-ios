import SwiftUI
import CoreMotion

struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage("onboarded") private var onboarded = false
    @State private var login = ""
    @State private var password = ""
    @State private var code = ""
    private enum Destination: Hashable { case room, profile }
    @State private var destination = Destination.room
    @State private var profilePath = NavigationPath()
    var body: some View {
        Group {
            if !onboarded {
                NavigationStack { GuideView { onboarded = true }.navigationTitle("RunTick 燃刻") }
            } else {
                // Native tab bars adopt Liquid Glass on iOS 26+. Keep their system
                // background and safe-area behavior, including Reduce Transparency.
                TabView(selection: tabSelection) {
                    Tab("房间详情", systemImage: "house", value: Destination.room) {
                        NavigationStack {
                            Group {
                                if model.user == nil { loginView }
                                else if let room = model.room {
                                    RoomView(model: room, leave: { Task { await model.perform { try await model.leave() } } })
                                } else { lobby }
                            }.navigationTitle("RunTick 燃刻")
                        }
                    }
                    Tab("我的", systemImage: "person.crop.circle", value: Destination.profile) {
                        NavigationStack(path: $profilePath) {
                            Group {
                                if let user = model.user { profileView(user) }
                                else { loginView }
                            }.navigationTitle("我的")
                        }
                    }
                }
            }
        }
        .overlay { if model.loading { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .safeAreaInset(edge: .bottom) {
            if !model.error.isEmpty {
                Text(model.error).font(.footnote).foregroundStyle(.red).padding()
                    .frame(maxWidth: .infinity).background(.regularMaterial)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onChange(of: model.user?.id) { _, _ in destination = .room; profilePath = NavigationPath() }
    }
    private var tabSelection: Binding<Destination> {
        Binding(get: { destination }, set: { target in
            guard !model.loading else { return }
            if target == .room {
                Task {
                    await model.perform {
                        try await model.openCurrentRoom()
                        destination = .room
                    }
                }
            } else {
                model.room?.interrupt()
                destination = .profile
            }
        })
    }
    private func profileView(_ user: User) -> some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Text(String(user.loginId.prefix(1)).uppercased())
                        .font(.largeTitle.bold()).frame(width: 72, height: 72)
                        .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
                    Text(user.loginId).font(.title2.bold())
                    Text("账号 ID：\(user.id)").foregroundStyle(.secondary)
                    Label("已登录", systemImage: "checkmark.circle.fill").foregroundStyle(.teal)
                }.frame(maxWidth: .infinity).padding(.vertical)
            }
            Section {
                if let api = model.api {
                    NavigationLink { HistoryView(api: api, user: user, room: nil) } label: {
                        Label("历史成绩", systemImage: "chart.xyaxis.line")
                    }
                }
                Button(role: .destructive) { Task { await model.perform { await model.logout() } } } label: {
                    Label("退出登录", systemImage: "power")
                }.disabled(model.loading)
            }
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
