#if canImport(SwiftUI)
import XCTest
import Foundation
@testable import RunTick

private final class FlowProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, body) = Self.handler?(request) ?? (200, "{\"ok\":true,\"data\":{}}")
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
        FlowProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FlowProtocol.self]
        return APIClient(baseURL: base, configuration: config)
    }
    private func clearRecords() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains("ios-flow-tests.invalid") { UserDefaults.standard.removeObject(forKey: key) }
    }
    func testRestoreKeepsMembershipInsteadOfPostingLeave() async {
        let client = api { request in
            if request.url!.path == "/api/auth/me" { return (200, "{\"ok\":true,\"data\":{\"user\":{\"id\":71,\"loginId\":\"runner\"}}}") }
            if request.url!.path == "/api/rooms/current" { return (200, "{\"ok\":true,\"data\":{\"room\":{\"code\":\"1234\",\"status\":\"active\"}}}") }
            if request.url!.path == "/api/rooms/leave" { XCTFail("Restoring must never leave the room") }
            return (200, "{\"ok\":true,\"data\":{}}")
        }
        let app = AppModel(api: client)
        await app.restore()
        XCTAssertEqual(app.user?.id, 71)
        XCTAssertEqual(app.room?.code, "1234")
        XCTAssertFalse(app.lobbyReady)
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
        model.clock = ClockMapping(offset: 13, uncertaintyMs: 2, averageRttMs: 2, sampledAt: ProcessInfo.processInfo.systemUptime)
        model.update(Race(id: "race", status: "ready", createdAt: 10, startAt: nil, finishAt: nil, elapsedMs: nil, uncertaintyMs: nil, startUserId: 72, finishUserId: 71, savedResult: nil))
        model.clock = ClockMapping(offset: 900, uncertaintyMs: 3, averageRttMs: 3, sampledAt: ProcessInfo.processInfo.systemUptime - 121)
        XCTAssertTrue(model.hasRecordingClock)
        model.press(); XCTAssertTrue(model.pressed)
        model.cancelPress(); model.release(at: 1000); XCTAssertNil(model.pending)
        model.press(); model.release(at: 1000)
        XCTAssertEqual(model.pending?.event.at, 1013)
        model.stop(); clearRecords()
    }
    func testTouchTimestampUsesEventClockRatherThanCallbackDelivery() {
        XCTAssertEqual(MonotonicClock.fromUptime(21.125) - MonotonicClock.fromUptime(21), 125, accuracy: 0.001)
    }
}
#endif
