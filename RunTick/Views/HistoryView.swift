import SwiftUI

struct HistoryView: View {
    let api: APIClient; let user: User; let room: String?
    @State private var data: HistoryData?
    @State private var records: [HistoryRecord] = []
    @State private var athleteId: Int
    @State private var distance = 0
    @State private var distanceIndex = 0.0
    @State private var sort = "date-desc"
    @State private var cursor: String?
    @State private var hasMore = false
    @State private var loading = false
    @State private var error = ""
    @State private var generation = UUID()
    private var options: [Int] { [0] + (data?.distances ?? []) }
    private var filter: String { "\(athleteId):\(distance):\(sort):\(user.avatar ?? "")" }
    init(api: APIClient,user: User,room: String?) { self.api=api;self.user=user;self.room=room;_athleteId=State(initialValue:user.id) }
    var body: some View {
        ScrollView {
            LazyVStack(spacing:18) {
                RTBrand()
                RTHero(badge:"训练档案",title:"历史成绩",subtitle:"每一次出发，都在向更好的自己靠近。")
                NavigationLink("单人起跑记录") { SoloHistoryView(api:api) }
                RTCard("筛选") {
                    if let data, data.athletes.count > 1 {
                        Picker("运动员",selection:$athleteId) { ForEach(data.athletes) { Text($0.id==user.id ? "我" : $0.loginId).tag($0.id) } }
                    }
                    let index=min(options.count-1,max(0,Int(distanceIndex)))
                    Text(options[index]==0 ? "距离：全部距离" : "距离：\(options[index]) 米")
                    Slider(value:$distanceIndex,in:0...Double(max(1,options.count-1)),step:1,onEditingChanged:{ editing in
                        if !editing { distance=options[min(options.count-1,max(0,Int(distanceIndex)))] }
                    }).disabled(options.count<2).accessibilityLabel("距离筛选")
                    Picker("排序",selection:$sort) { Text("最新").tag("date-desc");Text("最早").tag("date-asc");Text("最快").tag("result-asc");Text("最慢").tag("result-desc") }.pickerStyle(.segmented)
                }
                if records.isEmpty && !loading && error.isEmpty { Text("暂无成绩，完成计时后由终点填写距离并保存。") }
                ForEach(records) { record in
                    HistorySwipeRow(canDelete:record.athleteId==user.id,delete:{Task { await delete(record) }}) {
                        RTCard("\(record.distance) 米") {
                            Text(String(format:"%.3f 秒",record.elapsedMs/1000)).font(.title2.bold()).monospacedDigit()
                            Text(Date(timeIntervalSince1970:record.performedAt/1000).formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(RT.muted)
                            Text(ReactionResult.text(record.reactionMs,record.reactionStatus)).font(.caption).foregroundStyle(RT.muted)
                            if record.isPb { RTChip(text:"PB",lemon:true) }
                            if record.reactionStatus=="false_start" { RTChip(text:"抢跑",lemon:true) }
                        }
                    }.onAppear {
                        if record.id==records.suffix(2).first?.id && hasMore { Task { await load(reset:false) } }
                    }
                }
                if loading { ProgressView("加载成绩中…") }
                if !error.isEmpty { Button("重新加载成绩") {Task {await load(reset:records.isEmpty)}} }
                if !hasMore && !records.isEmpty { Text("已加载全部成绩").font(.caption).foregroundStyle(RT.muted) }
            }.padding(24)
        }.background(RT.aqua.opacity(0.05))
        .navigationTitle("历史成绩").navigationBarTitleDisplayMode(.inline)
        .task(id:filter) { await load(reset:true) }
        .onChange(of:athleteId) { _,_ in distance=0;distanceIndex=0 }
        .refreshable { await load(reset:true) }
        .rtErrorAlert($error)
    }
    private func load(reset: Bool) async {
        if !reset && (loading || !hasMore) { return }
        if reset { generation=UUID();records=[];cursor=nil;hasMore=false }
        let token=generation, requested=filter
        loading=true;error=""
        defer { if token==generation { loading=false } }
        let rule=sort.split(separator:"-")
        var query=URLComponents();query.path="/api/history"
        query.queryItems=[URLQueryItem(name:"athleteId",value:String(athleteId)),URLQueryItem(name:"limit",value:"5"),URLQueryItem(name:"sort",value:String(rule[0])),URLQueryItem(name:"direction",value:String(rule[1])),URLQueryItem(name:"includeTrend",value:"false")]
        if let cursor,!reset {query.queryItems?.append(URLQueryItem(name:"cursor",value:cursor))}
        if distance>0 {query.queryItems?.append(URLQueryItem(name:"distance",value:String(distance)))}
        if let room {query.queryItems?.append(URLQueryItem(name:"room",value:room))}
        do {
            let result:HistoryData=try await api.request(query.string!)
            guard !Task.isCancelled,token==generation,requested==filter else {return}
            data=result;hasMore=result.hasMore;cursor=result.nextCursor
            var seen=Set(records.map(\.id))
            records.append(contentsOf:result.records.filter {seen.insert($0.id).inserted})
            if !result.distances.contains(distance) && distance != 0 { distance=0;distanceIndex=0 }
        } catch is CancellationError {} catch { if token==generation && requested==filter {self.error=error.localizedDescription} }
    }
    private func delete(_ record:HistoryRecord) async {
        do {let _:EmptyResponse=try await api.request("/api/history/\(record.id)",method:"DELETE");await load(reset:true)}
        catch {self.error=error.localizedDescription}
    }
}

private struct HistorySwipeRow<Content:View>:View {
    let canDelete:Bool;let delete:()->Void;let content:Content
    init(canDelete:Bool,delete:@escaping ()->Void,@ViewBuilder content:()->Content) {self.canDelete=canDelete;self.delete=delete;self.content=content()}
    @State private var shift:CGFloat=0
    var body:some View {
        ZStack(alignment:.leading) {
            if canDelete && shift>0 { Button("删除",role:.destructive,action:delete).frame(width:64).accessibilityLabel("删除本条成绩") }
            content.offset(x:shift)
        }.clipped().simultaneousGesture(DragGesture(minimumDistance:20).onChanged { value in
            if canDelete && abs(value.translation.width)>abs(value.translation.height) {shift=min(76,max(0,value.translation.width))}
        }.onEnded {_ in withAnimation {shift=shift>32 ? 76 : 0}})
        .accessibilityActions {if canDelete {Button("删除",action:delete)}}
    }
}
