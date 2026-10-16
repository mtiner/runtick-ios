import SwiftUI
import Charts

struct HistoryView: View {
    let api: APIClient; let user: User; let room: String?
    @State private var data: HistoryData?
    @State private var athleteId = 0
    @State private var distance = 0
    @State private var sort = "date-desc"
    @State private var offset = 0
    @State private var loading = false
    @State private var error = ""
    @State private var selected: String?
    var filter: String { "\(athleteId):\(distance):\(sort):\(offset)" }
    var body: some View {
        RTPage {
            RTBrand().rtEntrance()
            RTHero(badge: "训练档案", title: "历史成绩", subtitle: "每一次出发，都在向更好的自己靠近。").rtEntrance(0.04)
            RTCard("筛选") {
                if let data, data.athletes.count > 1 {
                    Picker("运动员", selection: $athleteId) { ForEach(data.athletes) { athlete in Text(athlete.id == user.id ? "我" : athlete.loginId).tag(athlete.id) } }
                }
                Picker("距离", selection: $distance) { Text("全部距离").tag(0); ForEach(data?.distances ?? [], id: \.self) { Text("\($0) 米").tag($0) } }
                Picker("排序", selection: $sort) { Text("最新").tag("date-desc"); Text("最早").tag("date-asc"); Text("最快").tag("result-asc"); Text("最慢").tag("result-desc") }
            }
            if distance > 0, let points = data?.trend, !points.isEmpty {
                RTCard("\(distance) 米 · 最近 \(points.count) 次 · 越低越快") {
                    Chart(Array(points.enumerated()), id: \.element.id) { index, point in
                        LineMark(x: .value("次序", index + 1), y: .value("秒", point.elapsedMs / 1000)).interpolationMethod(.monotone)
                        PointMark(x: .value("次序", index + 1), y: .value("秒", point.elapsedMs / 1000))
                    }.foregroundStyle(RT.deep).frame(height: 200).chartYScale(domain: trendDomain(points))
                    ForEach(points) { point in
                        Button { selected = point.id } label: { HStack { Text(date(point.performedAt)); Spacer(); Text(String(format: "%.3f 秒", point.elapsedMs / 1000)); if selected == point.id { Image(systemName: "checkmark") } }.font(.caption) }
                    }
                }
            }
            if loading { ProgressView("加载成绩中…") }
            if !error.isEmpty { RTCard { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } } }
            if let data {
                RTCard("历史成绩") {
                    if data.records.isEmpty { Text("暂无成绩，完成计时后由终点填写距离并保存。") }
                    ForEach(data.records) { record in HStack {
                        VStack(alignment: .leading) { Text("\(record.distance) 米"); Text(date(record.performedAt)).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text(String(format: "%.3f 秒", record.elapsedMs / 1000)).monospacedDigit()
                        if record.isPb { RTChip(text: "PB", lemon: true) }
                    }.padding(.vertical, 10) }
                }
                HStack { Button("上一页") { offset = max(0, offset - 50) }.disabled(offset == 0 || loading); Spacer(); Button("下一页") { offset += 50 }.disabled(!data.hasMore || loading) }
            }
        }
        .navigationTitle("历史成绩").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task(id: filter) { await load() }
        .onChange(of: athleteId) { _, _ in distance = 0; offset = 0 }
        .onChange(of: distance) { _, _ in offset = 0 }
        .onChange(of: sort) { _, _ in offset = 0 }
        .refreshable { await load() }
    }
    func trendDomain(_ points: [TrendPoint]) -> ClosedRange<Double> {
        let values = points.map { $0.elapsedMs / 1000 }, low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max(0.1, (high - low) * 0.15)
        return max(0, low - pad)...(high + pad)
    }
    func date(_ value: Double) -> String { Date(timeIntervalSince1970: value / 1000).formatted(date: .abbreviated, time: .shortened) }
    func load() async {
        loading = true; error = ""
        let requested = filter
        defer { if requested == filter { loading = false } }
        let rule = sort.split(separator: "-")
        var query = URLComponents(); query.path = "/api/history"
        query.queryItems = [URLQueryItem(name: "athleteId", value: String(athleteId == 0 ? user.id : athleteId)), URLQueryItem(name: "sort", value: String(rule[0])), URLQueryItem(name: "direction", value: String(rule[1])), URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "includeTrend", value: "true")]
        if distance > 0 { query.queryItems?.append(URLQueryItem(name: "distance", value: String(distance))) }
        if let room { query.queryItems?.append(URLQueryItem(name: "room", value: room)) }
        do {
            let result: HistoryData = try await api.request(query.string!)
            guard !Task.isCancelled, requested == filter else { return }; data = result
        } catch is CancellationError {} catch { if requested == filter { self.error = error.localizedDescription } }
    }
}
