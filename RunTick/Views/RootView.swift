import SwiftUI
import CoreMotion

struct RootView: View {
    @Bindable var model: AppModel
    var guideIsVisible = true
    @AppStorage("onboarded") private var onboarded = false
    @State private var login = ""
    @State private var password = ""
    @State private var code = ""
    private enum Destination: Hashable { case room, starter, profile }
    @State private var destination = Destination.room
    @State private var profilePath = NavigationPath()
    var body: some View {
        Group {
            if !onboarded {
                NavigationStack { GuideView(automaticallyCheckNetwork: guideIsVisible) { onboarded = true }.toolbar(.hidden, for: .navigationBar) }
            } else {
                // Native tab bars adopt Liquid Glass on iOS 26+. Keep their system
                // background and safe-area behavior, including Reduce Transparency.
                TabView(selection: $destination) {
                    Tab("房间详情", systemImage: "house", value: Destination.room) {
                        NavigationStack {
                            Group {
                                if model.user == nil { loginView }
                                else if let room = model.room {
                                    RoomView(model: room, leave: { Task { await model.perform { room.error = ""; do { try await model.leave() } catch { room.error = error.localizedDescription } } } })
                                } else { lobby }
                            }.toolbar(.hidden, for: .navigationBar)
                        }
                    }
                    Tab("起跑发令", systemImage: "figure.run", value: Destination.starter) {
                        NavigationStack {
                            if let api = model.api, let user = model.user { SoloStartView(api: api, user: user) }
                            else { loginView }
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
        .rtErrorAlert($model.error, enabled: model.room == nil)
        .onChange(of: destination) { _, target in
            if target != .room { model.room?.interrupt() }
        }
        .task(id: destination) {
            guard destination == .room, model.user != nil, !model.loading else { return }
            do { try await model.openCurrentRoom() }
            catch is CancellationError {}
            catch {
                if let room = model.room { room.error = error.localizedDescription }
                else { model.error = error.localizedDescription }
            }
        }
        .onChange(of: model.user?.id) { _, _ in destination = .room; profilePath = NavigationPath() }
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
            NavigationLink("关于 RunTick") { AboutView() }
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
            Text("登录即可创建或加入计时房间").font(.footnote).foregroundStyle(RT.muted).frame(maxWidth: .infinity).padding(.top, 4)
            RTBrandFooter()
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
    var automaticallyCheckNetwork = true
    var continueTitle = "开始使用"
    var showHelp = true
    let proceed: () -> Void
    @State private var capabilities = "点击检查设备能力"
    private let motion = CMMotionManager()
    var body: some View {
        RTPage {
            RTBrand(showHelp: showHelp).rtEntrance()
            RTHero(badge: "开始之前", title: "两端协同，\n记录每次突破", subtitle: "起点发令，终点松手。\n让每一份努力，都有准确的刻度。").rtEntrance(0.04)
            RTCard {
                HStack(spacing: 20) {
                    Image(systemName: "figure.run").font(.system(size: 48, weight: .light)).foregroundStyle(RT.deep)
                    HStack(spacing: 5) { ForEach(0..<3) { _ in Circle().fill(RT.aqua).frame(width: 5, height: 5) } }
                    Image(systemName: "flag.checkered").font(.system(size: 42, weight: .light)).foregroundStyle(RT.deep)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
                Text("起点运动员播放原声发令；终点记录员提前按住屏幕，冲线时松手。").font(.subheadline).foregroundStyle(RT.muted).lineSpacing(5)
            }.rtEntrance(0.08)
            NetworkPreparationCard(automaticallyCheck: automaticallyCheckNetwork).rtEntrance(0.1)
            RTCard("设备准备") {
                Text(capabilities).font(.footnote).foregroundStyle(RT.muted)
                Button("检查设备能力") { capabilities = "陀螺仪：\(motion.isGyroAvailable ? "可用" : "不支持") · 加速度计：\(motion.isAccelerometerAvailable ? "可用" : "不支持")\n系统会话存储 · 房间内自动常亮" }

            }.rtEntrance(0.12)
            AudioPreparationCard().rtEntrance(0.14)
            Button(continueTitle, action: proceed).buttonStyle(RTButtonStyle()).accessibilityIdentifier("guide.continue").rtEntrance(0.16)
            Text("请使用手机扬声器。计时估算误差不含人工反应。").font(.caption).foregroundStyle(RT.muted).frame(maxWidth: .infinity)
            RTBrandFooter()
        }
    }
}
