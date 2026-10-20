#if canImport(SwiftUI)
import XCTest
import Foundation
@testable import RunTick

private final class FlowProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest) -> (Int, String)] = [:]
    static func register(_ handler: @escaping (URLRequest) -> (Int, String)) -> String {
        let id = UUID().uuidString
        lock.lock(); defer { lock.unlock() }
        handlers[id] = handler
        return id
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handlers[request.value(forHTTPHeaderField: "X-Flow-Test-ID") ?? ""]
        Self.lock.unlock()
        let (code, body) = handler?(request) ?? (200, "{\"ok\":true,\"data\":{}}")
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class AppFlowTests: XCTestCase {
    private let base = URL(string: "https://ios-flow-tests.invalid/")!
    private func api(_ handler: @escaping (URLRequest) -> (Int, String)) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["X-Flow-Test-ID": FlowProtocol.register(handler)]
        config.protocolClasses = [FlowProtocol.self]
        return APIClient(baseURL: base, configuration: config)
    }
    private func clearRecords() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains("ios-flow-tests.invalid") { UserDefaults.standard.removeObject(forKey: key) }
    }
    func testRestoreKeepsMembershipInsteadOfPostingLeave() async {
        let client = api { request in
            if request.url!.path == "/api/auth/me" { return (200, "{\"ok\":true,\"data\":{\"user\":{\"id\":71,\"loginId\":\"runner\"}}}") }
            if request.url!.path == "/api/rooms/current" { XCTFail("Cold restore must not request room membership"); return (200, "{\"ok\":true,\"data\":{\"room\":{\"code\":\"1234\",\"status\":\"active\"}}}") }
            if request.url!.path == "/api/rooms/leave" { XCTFail("Restoring must never leave the room") }
            return (200, "{\"ok\":true,\"data\":{}}")
        }
        let app = AppModel(api: client)
        await app.restore()
        XCTAssertEqual(app.user?.id, 71)
        XCTAssertNil(app.room)
        XCTAssertTrue(app.lobbyReady)
        app.clearSession(); clearRecords()
    }
    func testNoMembershipOpensLobbyWithoutNetworkLeave() async throws {
        let client = api { request in
            XCTAssertEqual(request.url!.path, "/api/rooms/current")
            return (200, "{\"ok\":true,\"data\":{\"room\":null}}")
        }
        let app = AppModel(api: client); app.user = User(id: 71, loginId: "runner")
        try await app.openCurrentRoom()
        XCTAssertTrue(app.lobbyReady); XCTAssertNil(app.room)
        app.clearSession()
    }
    func testFailedOldPendingDoesNotBlockLobbyOrOtherRecords() async throws {
        clearRecords()
        let client = api { request in
            let path = request.url!.path
            if path == "/api/rooms/current" { return (200, "{\"ok\":true,\"data\":{\"room\":null}}") }
            if path.contains("obsolete") { return (403, "{\"ok\":false,\"error\":{\"code\":\"FORBIDDEN\",\"message\":\"记录暂不可提交\"}}") }
            return (200, "{\"ok\":true,\"data\":{\"race\":null}}")
        }
        let app = AppModel(api: client); app.user = User(id: 71, loginId: "runner")
        let prefix = "pending:\(base.absoluteString):71:"
        for (code, id) in [("1234", "obsolete"), ("5678", "valid")] {
            let pending = PendingEvent(code: code, raceId: id, userId: 71, event: TimingEvent(kind: .finish, at: 1000, uncertaintyMs: 2))
            UserDefaults.standard.set(try JSONEncoder().encode(pending), forKey: prefix + code)
        }
        try await app.openCurrentRoom()
        XCTAssertTrue(app.lobbyReady)
        await app.replayPending()
        XCTAssertNotNil(UserDefaults.standard.data(forKey: prefix + "1234"))
        XCTAssertNil(UserDefaults.standard.data(forKey: prefix + "5678"))
        XCTAssertFalse(app.syncNotice.isEmpty)
        app.clearSession(); clearRecords()
    }
    func testExplicitLeaveDoesNotDeleteUnsentLocalData() async throws {
        clearRecords()
        let client = api { request in
            XCTAssertEqual(request.url!.path, "/api/rooms/leave")
            return (200, "{\"ok\":true,\"data\":{}}")
        }
        let app = AppModel(api: client); let user = User(id: 71, loginId: "runner"); app.user = user
        let model = RoomModel(code: "1234", user: user, api: client); app.room = model
        let bytes = try JSONEncoder().encode(PendingEvent(code: "1234", raceId: "unsent", userId: 71, event: TimingEvent(kind: .finish, at: 1000, uncertaintyMs: 2)))
        UserDefaults.standard.set(bytes, forKey: model.pendingKey)
        try await app.leave()
        XCTAssertNil(app.room); XCTAssertTrue(app.lobbyReady)
        XCTAssertEqual(UserDefaults.standard.data(forKey: model.pendingKey), bytes)
        app.clearSession(); clearRecords()
    }
    func testRecordingClockSurvivesLongWaitAndCancellingTouchDoesNotCapture() {
        clearRecords()
        let client = api { _ in (200, "{\"ok\":true,\"data\":{\"race\":null}}") }
        let model = RoomModel(code: "1234", user: User(id: 71, loginId: "runner"), api: client)
        model.clock = ClockMapping(offset: 13, uncertaintyMs: 2, averageRttMs: 2, sampledAt: MonotonicClock.now() / 1000)
        model.update(Race(id: "race", status: "ready", createdAt: 10, startAt: nil, finishAt: nil, elapsedMs: nil, uncertaintyMs: nil, startUserId: 72, finishUserId: 71, savedResult: nil))
        model.clock = ClockMapping(offset: 900, uncertaintyMs: 3, averageRttMs: 3, sampledAt: MonotonicClock.now() / 1000 - 121)
        XCTAssertTrue(model.hasRecordingClock)
        model.press(); XCTAssertTrue(model.pressed)
        let eventAt = MonotonicClock.now()
        model.cancelPress(); model.release(at: eventAt); XCTAssertNil(model.pending)
        model.press(); model.release(at: eventAt)
        XCTAssertEqual(model.pending?.event.at, eventAt + 13)
        model.stop(); clearRecords()
    }
    func testUnsentTimingPreventsCreatingAnUnrecordableNewRound() async {
        let client = api { _ in XCTFail("A new race must not be created while the previous timestamp is pending"); return (200, "{\"ok\":true,\"data\":{}}") }
        let model = RoomModel(code: "1234", user: User(id: 71, loginId: "runner"), api: client)
        model.ready = true; model.connected = true
        model.members = [Member(loginId: "runner", deviceRole: .start, online: true)]
        model.clock = ClockMapping(offset: 0, uncertaintyMs: 2, averageRttMs: 2, sampledAt: MonotonicClock.now() / 1000)
        model.pending = PendingEvent(code: "1234", raceId: "previous", userId: 71, event: TimingEvent(kind: .start, at: 1000, uncertaintyMs: 2))
        await model.beginRecording()
        XCTAssertNil(model.race); XCTAssertTrue(model.error.contains("尚未同步"))
        model.stop()
    }
    func testPreviousRoundIsArchivedWithoutBlockingTheCurrentRound() throws {
        clearRecords()
        let client = api { _ in (200, "{\"ok\":true,\"data\":{}}") }
        let old = PendingEvent(code: "1234", raceId: "old-round", userId: 71, event: TimingEvent(kind: .start, at: 1000, uncertaintyMs: 2))
        let model = RoomModel(code: "1234", user: User(id: 71, loginId: "runner"), api: client)
        let bytes = try JSONEncoder().encode(old)
        model.pending = old; UserDefaults.standard.set(bytes, forKey: model.pendingKey)
        model.update(Race(id: "new-round", status: "ready", createdAt: 20, startAt: nil, finishAt: nil, elapsedMs: nil, uncertaintyMs: nil, startUserId: 71, finishUserId: 72, savedResult: nil))
        XCTAssertNil(model.pending)
        XCTAssertNil(UserDefaults.standard.data(forKey: model.pendingKey))
        XCTAssertEqual(UserDefaults.standard.data(forKey: model.pendingKey + ":old-round"), bytes)
        model.stop(); clearRecords()
    }
    func testCancelledRoundKeepsItsUnsentDataOutsideTheCurrentSlot() throws {
        clearRecords()
        let client = api { _ in (200, "{\"ok\":true,\"data\":{}}") }
        let model = RoomModel(code: "1234", user: User(id: 71, loginId: "runner"), api: client)
        let old = PendingEvent(code: "1234", raceId: "cancelled-round", userId: 71, event: TimingEvent(kind: .start, at: 1000, uncertaintyMs: 2))
        let bytes = try JSONEncoder().encode(old); model.pending = old
        UserDefaults.standard.set(bytes, forKey: model.pendingKey)
        model.update(Race(id: "cancelled-round", status: "cancelled", createdAt: 20, startAt: nil, finishAt: nil, elapsedMs: nil, uncertaintyMs: nil, startUserId: 71, finishUserId: 72, savedResult: nil))
        XCTAssertNil(model.pending)
        XCTAssertEqual(UserDefaults.standard.data(forKey: model.pendingKey + ":cancelled-round"), bytes)
        model.stop(); clearRecords()
    }
    func testFailedCalibrationDoesNotClaimItSucceeded() async {
        let client = api { _ in (503, "{\"ok\":false,\"error\":{\"code\":\"UNAVAILABLE\",\"message\":\"暂不可用\"}}") }
        let model = RoomModel(code: "1234", user: User(id: 71, loginId: "runner"), api: client)
        await model.fire()
        XCTAssertNil(model.clock)
        XCTAssertTrue(model.error.contains("服务暂时不可用"))
        XCTAssertFalse(model.error.contains("已完成"))
        model.stop()
    }
    func testUnsupportedRemotePlanNeverFallsBackToUnconfirmedLocalSettings() async {
        let client = api { _ in XCTFail("Invalid remote settings must be rejected locally"); return (200, "{\"ok\":true,\"data\":{}}") }
        let model = RoomModel(code: "1234", user: User(id: 71, loginId: "runner"), api: client)
        model.race = Race(id: "remote", status: "ready", createdAt: 20, startAt: nil, finishAt: nil, elapsedMs: nil, uncertaintyMs: nil, startUserId: 71, finishUserId: 72, savedResult: nil, starterSettings: [StageDelay(random: false, min: 30, max: 30)])
        await model.fire(allowReducedVolume: true)
        XCTAssertTrue(model.error.contains("0～10")); XCTAssertFalse(model.firing); XCTAssertNil(model.pending)
        model.stop()
    }
    func testTouchTimestampUsesEventClockRatherThanCallbackDelivery() {
        XCTAssertEqual(MonotonicClock.fromUptime(21.125) - MonotonicClock.fromUptime(21), 125, accuracy: 0.001)
    }
    func testAvatarSaveSendsRawFilenameAndRejectedSaveKeepsCurrentProfile() async throws {
        var rejected = false
        let client=api { request in
            XCTAssertEqual(request.url?.path,"/api/auth/avatar")
            XCTAssertEqual(request.httpMethod,"PATCH")
            if rejected { return (400,#"{"ok":false,"error":{"code":"VALIDATION","message":"请选择图库头像"}}"#) }
            return (200,#"{"ok":true,"data":{"user":{"id":71,"loginId":"runner","avatar":"Nike Dragonfly.png"}}}"#)
        }
        let app=AppModel(api:client); app.user=User(id:71,loginId:"runner")
        try await app.updateAvatar("Nike Dragonfly.png")
        XCTAssertEqual(app.user?.avatar,"Nike Dragonfly.png")
        rejected=true
        do { try await app.updateAvatar("Nike Maxfly 2.png"); XCTFail("Rejected save must fail") } catch {}
        XCTAssertEqual(app.user?.avatar,"Nike Dragonfly.png")
        app.clearSession()
    }

    func testRepeatedRoomResumeReusesFreshMappingAndStatusHidesDiagnostics() async {
        let client=api { _ in (200,"{\"ok\":true,\"data\":{}}") }
        let room=RoomModel(code:"4932",user:User(id:71,loginId:"runner"),api:client)
        defer { room.stop() }
        var mapping=ClockMapping(offset:1,uncertaintyMs:2,averageRttMs:2,sampledAt:MonotonicClock.now()/1000)
        mapping.server="f.m.suning.com"; mapping.validSamples=8
        room.clock=mapping
        for _ in 0..<3 { room.resume() }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(room.syncing)
        XCTAssertTrue(room.syncDetail.isEmpty, "A fresh mapping must not start a new sampling round")
        XCTAssertEqual(room.syncSummary,"时间已同步")
        room.syncError="f.m.suning.com RTT rejected"
        XCTAssertEqual(room.syncSummary,"时间同步质量下降，请重新同步")
        room.clock=ClockMapping(offset:1,uncertaintyMs:2,averageRttMs:2,sampledAt:(MonotonicClock.now()-121000)/1000)
        XCTAssertEqual(room.syncSummary,"时间同步已过期，请重新同步")
    }

    func testCalibrationFailureStaysInlineAndPreservesActionError() async {
        let client = api { _ in (200, "{\"ok\":true,\"data\":{}}") }
        let room = RoomModel(code: "4932", user: User(id: 71, loginId: "runner"), api: client)
        let source = SuningTimeClient.shared
        let previous = source.exchange
        source.exchange = { throw ClientError.message("time source unavailable") }
        defer { source.exchange = previous; room.stop() }
        room.error = "保存设置失败"
        await room.calibrate(force: true)
        XCTAssertFalse(room.syncError.isEmpty)
        XCTAssertEqual(room.error, "保存设置失败", "Background calibration must not overwrite or open an action alert")
        XCTAssertEqual(room.syncSummary, "时间同步失败，请重试")
    }

}
#endif
