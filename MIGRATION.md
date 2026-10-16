import XCTest
@testable import RunTick

final class TimingTests: XCTestCase {
    func testRoleChangesImmediatelyAndBlocksAnotherRequest() {
        var state = RoleSelection()
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
        XCTAssertEqual(state.displayed(serverRole: .start), .finish)
        XCTAssertTrue(state.saving)
        XCTAssertFalse(state.begin(.start, serverRole: .start))
        state.receivedServerState()
        XCTAssertEqual(state.displayed(serverRole: .start), .finish)
    }
    func testFailedRoleChangeRollsBack() {
        var state = RoleSelection()
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
        state.failed()
        XCTAssertFalse(state.saving)
        XCTAssertEqual(state.displayed(serverRole: .start), .start)
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
    }
    func testRoleRequestCompletesBeforeSocketAcknowledgement() {
        var state = RoleSelection()
        XCTAssertFalse(state.begin(.start, serverRole: .start))
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
        state.succeeded(serverRole: .start)
        XCTAssertFalse(state.saving)
        XCTAssertEqual(state.displayed(serverRole: .start), .finish)
        state.receivedServerState()
        XCTAssertEqual(state.displayed(serverRole: .finish), .finish)
        XCTAssertTrue(state.begin(.start, serverRole: .finish))
    }
    func testSocketAcknowledgementBeforeRoleRequestReturns() {
        var state = RoleSelection()
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
        state.receivedServerState()
        XCTAssertTrue(state.saving)
        state.succeeded(serverRole: .finish)
        XCTAssertNil(state.optimistic)
        XCTAssertFalse(state.saving)
    }
    func testProductionGatewayIsBuiltIn() {
        XCTAssertEqual(AppConfiguration.serverURL.scheme, "https")
        XCTAssertEqual(AppConfiguration.serverURL.host, "app.runtick.cc")
        XCTAssertEqual(AppConfiguration.serverURL.path, "/")
    }
    func testCurrentRoomNavigationResponse() throws {
        let decoder = JSONDecoder()
        let empty = try decoder.decode(CurrentRoomResponse.self, from: Data(#"{"room":null}"#.utf8))
        XCTAssertNil(empty.room)
        let active = try decoder.decode(CurrentRoomResponse.self, from: Data(#"{"room":{"code":"0123"}}"#.utf8))
        XCTAssertEqual(active.room?.code, "0123")
        XCTAssertNil(active.room?.status)
    }
    func testClockOffsetAndUncertainty() throws {
        let mapping = try ClockMapping.average([ClockSample(sent: 1000, received: 1020, serverReceived: 1015, serverSent: 1015), ClockSample(sent: 2000, received: 2024, serverReceived: 2017, serverSent: 2017)])
        XCTAssertEqual(mapping.offset, 5, accuracy: 0.001)
        XCTAssertEqual(mapping.averageRttMs, 22, accuracy: 0.001)
        XCTAssertEqual(mapping.uncertaintyMs, 12, accuracy: 0.001)
    }
    func testRejectsUnusableClock() {
        XCTAssertThrowsError(try ClockMapping.average([]))
        XCTAssertThrowsError(try ClockMapping.average([ClockSample(sent: 0, received: 1000, serverReceived: 500, serverSent: 500)]))
    }
    func testDelayValidation() {
        XCTAssertTrue(StageDelay.defaults.allSatisfy(\.valid))
        XCTAssertFalse(StageDelay(random: true, min: 5, max: 2).valid)
        XCTAssertFalse(StageDelay(random: false, min: .nan, max: 2).valid)
        XCTAssertFalse(StageDelay(random: false, min: 31, max: 31).valid)
        XCTAssertEqual(StageDelay(random: false, min: 2, max: 3).sample(), 2)
    }
    func testOriginalTimestampSurvivesPersistence() throws {
        let pending = PendingEvent(code: "0123", raceId: "r1", userId: 7, event: TimingEvent(kind: .finish, at: 12345.678, uncertaintyMs: 12))
        let decoded = try JSONDecoder().decode(PendingEvent.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(decoded.event.at, pending.event.at)
        XCTAssertEqual(decoded.code, "0123")
    }
    func testLatePollCannotUndoCompletedRace() throws {
        func race(_ status: String, _ start: String, _ finish: String) throws -> Race {
            let json = "{\"id\":\"r\",\"status\":\"\(status)\",\"createdAt\":1,\"startAt\":\(start),\"finishAt\":\(finish),\"startUserId\":1,\"finishUserId\":2}"
            return try JSONDecoder().decode(Race.self, from: Data(json.utf8))
        }
        let completed = try race("completed", "10", "20")
        XCTAssertFalse(completed.accepts(try race("running", "10", "null")))
        XCTAssertTrue(completed.accepts(completed))
    }
}

## 标签切换与帮助入口

TabView 直接绑定选中标签，切换立即生效；返回房间时以 task(id:) 后台查询现有房间，不显示全局加载遮罩，不在请求完成后重设标签。离开标签会取消查询，API 返回后也检查取消，避免迟到响应重建页面。

房间品牌页头恢复退出房间按钮，底部使用明确“退出房间”文案。共享品牌页头恢复使用说明按钮，说明以原生 sheet 呈现，含“前往权限检测页”文字链接；检测页通过导航返回说明，保留房间/登录/首次引导状态。

## 发令设置与终点触控精简

活动轮次隐藏房间状态/RTT/校时卡片，仅在无可用校时映射时提供必要的恢复控件。固定等待为 5–30 秒单滑块；随机等待为同一轨道两个可拖动端点，按整秒选择上下限。旧配置自动归一化到新范围，默认 5 秒 / 5 秒 / 随机 5–10 秒。双端滑块支持 VoiceOver 调整，不允许端点交叉。终点底层说明层移除重复返回与重新校时控件，操作层各仅保留一份。

已有活动轮次和时钟映射时，暂时网络错误不以弹窗打断本机采集；断线不要求两端重新就绪。仍保留两分钟校时新鲜度、显式退出/服务端取消、前后台切换的保护，不能将网络断线理解为永久离线运行。已采集事件按原时间戳保留并重试。DEBUG 截图新增起点和终点实际页面，使用内存预览状态，不发送业务请求。
