import SwiftUI

struct StageDelayControl: View {
    let title: String
    @Binding var stage: StageDelay
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer(minLength: 8)
                Toggle("随机", isOn: $stage.random).font(.caption).fixedSize()
                .onChange(of: stage.random) { _, random in
                    if random && stage.max == stage.min && stage.min < 10 { stage.max = min(10, stage.min + 5) }
                }
            }
            HStack {
                Text(stage.random ? "随机范围" : "固定等待").foregroundStyle(RT.muted)
                Spacer()
                Text(stage.random ? "\(Int(stage.min))–\(Int(stage.max)) 秒" : "\(Int(stage.min)) 秒").monospacedDigit().fontWeight(.semibold)
            }.font(.subheadline)
            if stage.random { DelayRangeSlider(stage: $stage) }
            else {
                Slider(value: Binding(get: { stage.min }, set: { value in stage.min = value; stage.max = max(stage.max, value) }), in: 0...10, step: 1)
                    .accessibilityLabel("\(title)，固定等待秒数")
            }
            HStack { Text("0 秒"); Spacer(); Text("10 秒") }.font(.caption).foregroundStyle(RT.muted)
        }.padding(.vertical, 8)
    }
}

/// One continuous track, two independently adjustable, non-crossing handles.
private struct DelayRangeSlider: View {
    @Binding var stage: StageDelay
    @State private var lowerActive: Bool?
    @Namespace private var coordinates
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 44)
            let low = 22 + stage.min / 10 * width
            let high = 22 + stage.max / 10 * width
            ZStack(alignment: .leading) {
                Capsule().fill(RT.ink.opacity(0.10)).frame(height: 5).padding(.horizontal, 22)
                Capsule().fill(RT.deep).frame(width: max(0, high - low), height: 5).offset(x: low)
                handle(lower: true).position(x: low, y: 22)
                handle(lower: false).position(x: high, y: 22)
            }
            .frame(height: 44).contentShape(Rectangle()).coordinateSpace(name: coordinates)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(coordinates))
                .onChanged { drag in
                    guard enabled else { return }
                    if lowerActive == nil {
                        let a = abs(drag.startLocation.x - low), b = abs(drag.startLocation.x - high)
                        lowerActive = abs(a - b) < 1 ? drag.translation.width < 0 : a < b
                    }
                    let value = 0 + (drag.location.x - 22) / width * 10
                    if lowerActive == true { stage.setLower(value) } else { stage.setUpper(value) }
                }.onEnded { _ in lowerActive = nil })
        }.frame(height: 44).opacity(enabled ? 1 : 0.45)
    }
    private func handle(lower: Bool) -> some View {
        Circle().fill(.white).frame(width: 26, height: 26)
            .overlay { Circle().strokeBorder(RT.deep.opacity(0.3), lineWidth: 1) }
            .shadow(color: RT.ink.opacity(0.15), radius: 3, y: 2)
            .frame(width: 44, height: 44)
            .accessibilityElement().accessibilityLabel(lower ? "随机等待下限" : "随机等待上限")
            .accessibilityValue("\(Int(lower ? stage.min : stage.max)) 秒")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                let change: Double = direction == .increment ? 1 : -1
                if lower { stage.setLower(stage.min + change) } else { stage.setUpper(stage.max + change) }
            }
    }
}


struct UserStarterSettingsView: View {
    let api: APIClient
    @State private var stages = StageDelay.defaults
    @State private var loading = true
    @State private var saving = false
    @State private var error = ""
    @State private var saved = false
    var body: some View {
        RTPage {
            RTHero(badge: "个人偏好", title: "起跑设置", subtitle: "保存到当前账号；担任起点时用于新一轮发令。")
            RTCard("发令时间") {
                Toggle("检测起跑反应时", isOn: Binding(get: { stages[0].reactionEnabled == true }, set: { stages[0].reactionEnabled = $0 }))
                Text("仅检测枪声后手机的移动；各就各位和预备期间可以移动。检测失败不影响正式计时。").font(.footnote).foregroundStyle(RT.muted)
                Toggle("播放预备口令", isOn: Binding(get: { stages[1].enabled != false }, set: { stages[1].enabled = $0 }))
                ForEach(0..<3, id: \.self) { i in
                    if i != 1 || stages[1].enabled != false {
                        StageDelayControl(title: ["开始 → 各就各位", "各就各位结束 → 预备", stages[1].enabled != false ? "预备结束 → 枪声" : "各就各位结束 → 枪声"][i], stage: $stages[i])
                    }
                }
                Text("是否播放各就各位在每次开始时选择；跳过时也跳过该段等待。修改仅对新一轮生效。").font(.footnote).foregroundStyle(RT.muted)
            }.disabled(loading || saving)
            if loading { ProgressView(); if !error.isEmpty { Button("重新加载") { Task { await load() } } } }
            Button(saving ? "正在保存…" : "保存设置") { Task { await save() } }.buttonStyle(RTButtonStyle()).disabled(loading || saving)
            if saved { RTNotice(text: "起跑设置已保存到账号") }
        }.navigationTitle("起跑设置").navigationBarTitleDisplayMode(.inline).rtErrorAlert($error).task { await load() }
    }
    private func load() async {
        loading = true
        do { let value: StarterSettingsResponse = try await api.request("/api/auth/starter-settings"); stages = value.starterSettings; loading = false }
        catch { self.error = error.localizedDescription }
    }
    private func save() async {
        saving = true; saved = false; defer { saving = false }
        do {
            let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stages))
            let value: StarterSettingsResponse = try await api.request("/api/auth/starter-settings", method: "PUT", body: ["starterSettings": body])
            stages = value.starterSettings; saved = true
        } catch { self.error = error.localizedDescription }
    }
}
