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
                    if random && stage.max == stage.min && stage.min < 30 { stage.max = min(30, stage.min + 5) }
                }
            }
            HStack {
                Text(stage.random ? "随机范围" : "固定等待").foregroundStyle(RT.muted)
                Spacer()
                Text(stage.random ? "\(Int(stage.min))–\(Int(stage.max)) 秒" : "\(Int(stage.min)) 秒").monospacedDigit().fontWeight(.semibold)
            }.font(.subheadline)
            if stage.random { DelayRangeSlider(stage: $stage) }
            else {
                Slider(value: Binding(get: { stage.min }, set: { value in stage.min = value; stage.max = max(stage.max, value) }), in: 5...30, step: 1)
                    .accessibilityLabel("\(title)，固定等待秒数")
            }
            HStack { Text("5 秒"); Spacer(); Text("30 秒") }.font(.caption).foregroundStyle(RT.muted)
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
            let low = 22 + (stage.min - 5) / 25 * width
            let high = 22 + (stage.max - 5) / 25 * width
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
                    let value = 5 + (drag.location.x - 22) / width * 25
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
