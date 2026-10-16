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
                NavigationStack { GuideView { onboarded = true }.toolbar(.hidden, for: .navigationBar) }
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
                            }.toolbar(.hidden, for: .navigationBar)
                        }
                    }
                    Tab("我的", systemImage: "person.crop.circle", value: Destination.profile) {
                        NavigationStack(path: $profilePath) {
                            Group {
                                if let user = model.user { profileView(user) }
                                else { loginView }
                            }.toolbar(.hidden, for: .navigationBar)
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
        RTPage {
            RTBrand().rtEntrance()
            RTHero(badge: "个人中心", title: "我的").rtEntrance(0.04)
            RTCard {
                VStack(spacing: 14) {
                    Text(String(user.loginId.prefix(1)).uppercased())
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .frame(width: 72, height: 72).background(RT.aqua.opacity(0.22), in: RoundedRectangle(cornerRadius: 22))
                    Text(user.loginId).font(.title2.bold())
                    Text("账号 ID：\(user.id)").font(.footnote).foregroundStyle(RT.muted)
                    Label("已登录", systemImage: "circle.fill").font(.caption).foregroundStyle(RT.deep)
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
            }.rtEntrance(0.08)
            if let api = model.api {
                NavigationLink { HistoryView(api: api, user: user, room: nil) } label: {
                    HStack { Image(systemName: "chart.xyaxis.line"); Text("历史成绩"); Spacer(); Image(systemName: "arrow.right") }
                }.rtEntrance(0.12)
            }
            Button { Task { await model.perform { await model.logout() } } } label: { Label("退出登录", systemImage: "power") }
                .disabled(model.loading).rtEntrance(0.16)
        }
    }
    var loginView: some View {
        RTPage {
            RTBrand().rtEntrance()
            RTHero(badge: "账号登录", title: "登录，开始计时", subtitle: "首次使用的 ID 将自动创建账号，\n请记住 ID 和密码。").rtEntrance(0.04)
            RTCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("用户 ID").font(.subheadline.weight(.medium))
                    TextField("自定义 ID，全局唯一", text: $login).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().rtField()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("密码").font(.subheadline.weight(.medium))
                    SecureField("请输入密码", text: $password).textContentType(.password).keyboardType(.numberPad).rtField()
                }
                Button(model.loading ? "登录中…" : "登录") { Task { await model.perform { try await model.login(id: login, password: password); password = "" } } }
                    .buttonStyle(RTButtonStyle()).disabled(model.loading).accessibilityIdentifier("login.submit")
            }.rtEntrance(0.08)
            DisclosureGroup("连接服务") {
                TextField("后端 HTTPS 根地址", text: $model.serverAddress).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().rtField()
            }.font(.footnote).foregroundStyle(RT.muted).padding(.horizontal, 4)
            Text("登录即可创建或加入计时房间").font(.footnote).foregroundStyle(RT.muted).frame(maxWidth: .infinity).padding(.top, 4)
        }
    }
    var lobby: some View {
        RTPage {
            RTBrand().rtEntrance()
            RTHero(badge: "房间入口", title: "创建或加入房间", subtitle: "两台手机，一个房间。\n准备好，就一起出发。").rtEntrance(0.04)
            RTCard {
                Image(systemName: "plus.circle").font(.system(size: 32, weight: .light)).foregroundStyle(RT.deep)
                Text("创建房间").font(.title3.bold())
                Text("邀请另一台手机加入，开始这一组训练。").font(.subheadline).foregroundStyle(RT.muted)
                Button("立即创建") { Task { await model.perform { try await model.enter() } } }
                    .buttonStyle(RTButtonStyle()).disabled(!model.lobbyReady || model.loading)
            }.rtEntrance(0.08)
            RTCard {
                HStack { Image(systemName: "rectangle.grid.2x2").foregroundStyle(RT.deep); Text("加入房间").font(.title3.bold()) }
                RTCodeInput(code: $code)
                    .onChange(of: code) { _, value in
                        code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4))
                        if code.count == 4 && !model.loading && model.lobbyReady { Task { await model.perform { try await model.enter(code: code) } } }
                    }
                Button("加入房间") { Task { await model.perform { try await model.enter(code: code) } } }.disabled(code.count != 4 || !model.lobbyReady || model.loading)
            }.rtEntrance(0.12)
            if !model.lobbyReady { Button("重试退出旧房间") { Task { await model.perform { try await model.leave() } } } }
        }
    }
}

struct GuideView: View {
    let proceed: () -> Void
    @State private var capabilities = "点击检查设备能力"
    @State private var audio = StarterAudio()
    private let motion = CMMotionManager()
    var body: some View {
        RTPage {
            RTBrand().rtEntrance()
            RTHero(badge: "开始之前", title: "两端协同，\n记录每次突破", subtitle: "起点发令，终点松手。\n让每一份努力，都有准确的刻度。").rtEntrance(0.04)
            RTCard {
                HStack(spacing: 20) {
                    Image(systemName: "figure.run").font(.system(size: 48, weight: .light)).foregroundStyle(RT.deep)
                    HStack(spacing: 5) { ForEach(0..<3) { _ in Circle().fill(RT.aqua).frame(width: 5, height: 5) } }
                    Image(systemName: "flag.checkered").font(.system(size: 42, weight: .light)).foregroundStyle(RT.deep)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
                Text("起点运动员播放原声发令；终点记录员提前按住屏幕，冲线时松手。").font(.subheadline).foregroundStyle(RT.muted).lineSpacing(5)
            }.rtEntrance(0.08)
            RTCard("设备准备") {
                Text(capabilities).font(.footnote).foregroundStyle(RT.muted)
                Button("检查设备能力") { capabilities = "陀螺仪：\(motion.isGyroAvailable ? "可用" : "不支持") · 加速度计：\(motion.isAccelerometerAvailable ? "可用" : "不支持")\n系统会话存储 · 房间内自动常亮" }
                Button("试听发令原声") { Task { do { try await audio.play(settings: Array(repeating: StageDelay(random: false, min: 0, max: 0), count: 3), cue: { capabilities = $0 }, gun: { _, _ in }) } catch { capabilities = error.localizedDescription } } }
            }.rtEntrance(0.12)
            Button("开始使用", action: proceed).buttonStyle(RTButtonStyle()).accessibilityIdentifier("guide.continue").rtEntrance(0.16)
            Text("请使用手机扬声器。计时估算误差不含人工反应。").font(.caption).foregroundStyle(RT.muted).frame(maxWidth: .infinity)
        }.onDisappear { audio.stop() }
    }
}
