import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RunTick

final class TimingTests: XCTestCase {
    func testMotionRequiresStableBaselineAndSustainedMovement() {
        var gate = MotionGate()
        gate.sample(at: 0, acceleration: 2, rotation: 1)
        XCTAssertNil(gate.movedAt)
        for at in stride(from: 100.0, through: 700.0, by: 10) { gate.sample(at: at, acceleration: 0.01, rotation: 0.01) }
        XCTAssertTrue(gate.ready)
        gate.sample(at: 710, acceleration: 2, rotation: 1)
        gate.sample(at: 720, acceleration: 0, rotation: 0)
        XCTAssertNil(gate.movedAt)
        for at in stride(from: 800.0, through: 840.0, by: 10) { gate.sample(at: at, acceleration: 0.7, rotation: 0.5) }
        XCTAssertEqual(gate.movedAt, 800)
    }
    func testRecordingSettingsTravelWithRaceAndLegacyRacesStillDecode() throws {
        let legacy = #"{"id":"round","status":"ready","createdAt":123,"startUserId":1,"finishUserId":2}"#
        let decoder = JSONDecoder()
        let old = try decoder.decode(Race.self, from: Data(legacy.utf8))
        XCTAssertNil(old.starterSettings)
        var planned = old
        planned.starterSettings = [StageDelay(random: false, min: 7, max: 7), StageDelay(random: true, min: 8, max: 12), StageDelay(random: true, min: 5, max: 30)]
        let restored = try decoder.decode(Race.self, from: JSONEncoder().encode(planned))
        XCTAssertEqual(restored.starterSettings, planned.starterSettings)
        XCTAssertEqual(restored.startUserId, 1)
        XCTAssertEqual(restored.finishUserId, 2)
    }

    func testSavedSessionSurvivesEncodingWithoutExtendingExpiry() throws {
        let server = URL(string: "https://app.runtick.cc/")!
        let expiry = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 3600)
        let cookie = HTTPCookie(properties: [.name: "runtick_session", .value: "test-token", .domain: "app.runtick.cc", .path: "/", .secure: "TRUE", .expires: expiry])!
        let data = try JSONEncoder().encode(SavedSessionCookie(cookie))
        let restored = try JSONDecoder().decode(SavedSessionCookie.self, from: data)
        let validTime = expiry.addingTimeInterval(-60)
        XCTAssertEqual(restored.cookie(for: server, now: validTime)?.value, "test-token")
        XCTAssertEqual(restored.cookie(for: server, now: validTime)?.expiresDate, expiry)
        XCTAssertNil(restored.cookie(for: server, now: expiry))
        XCTAssertNil(restored.cookie(for: URL(string: "https://other.example/")!, now: validTime))
        XCTAssertNil(restored.cookie(for: URL(string: "http://app.runtick.cc/")!, now: validTime))
    }
    #if os(iOS)
    func testKeychainSessionSurvivesStoreRecreationAndLogoutClearsIt() throws {
        let server = URL(string: "https://session-test-\(UUID().uuidString).example/")!
        let store = SessionStore(server: server)
        defer { store.clear() }
        let cookie = HTTPCookie(properties: [.name: "runtick_session", .value: "test-token", .domain: server.host!, .path: "/", .secure: "TRUE", .expires: Date().addingTimeInterval(3600)])!
        try store.save(cookie, user: User(id: 1, loginId: "test"))
        let recreated = SessionStore(server: server)
        XCTAssertEqual(recreated.restore()?.value, "test-token")
        XCTAssertEqual(recreated.read()?.user?.loginId, "test")
        recreated.clear()
        XCTAssertNil(SessionStore(server: server).restore())
        XCTAssertNil(SessionStore(server: server).read()?.user)
    }
    #endif

    func testRoleChangesImmediatelyAndQueuesLatestTap() {
        var state = RoleSelection()
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
        XCTAssertEqual(state.displayed(serverRole: .start), .finish)
        XCTAssertTrue(state.saving)
        XCTAssertFalse(state.begin(.start, serverRole: .start))
        XCTAssertEqual(state.displayed(serverRole: .start), .start)
        state.receivedServerState(serverRole: .finish)
        XCTAssertEqual(state.displayed(serverRole: .finish), .start)
        state.succeeded(serverRole: .finish)
        XCTAssertEqual(state.inFlight, .start)
        state.succeeded(serverRole: .start)
        XCTAssertFalse(state.saving)
        XCTAssertEqual(state.displayed(serverRole: .start), .start)
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
        state.receivedServerState(serverRole: .finish)
        XCTAssertEqual(state.displayed(serverRole: .finish), .finish)
        XCTAssertTrue(state.begin(.start, serverRole: .finish))
    }
    func testSocketAcknowledgementBeforeRoleRequestReturns() {
        var state = RoleSelection()
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
        state.receivedServerState(serverRole: .finish)
        XCTAssertTrue(state.saving)
        state.succeeded(serverRole: .finish)
        XCTAssertNil(state.optimistic)
        XCTAssertFalse(state.saving)
    }
    func testSupersededRoleFailurePreservesLatestChoice() {
        var state = RoleSelection()
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
        XCTAssertFalse(state.begin(.start, serverRole: .start))
        state.failed()
        XCTAssertEqual(state.inFlight, .start)
        XCTAssertEqual(state.displayed(serverRole: .finish), .start)
        state.failed()
        XCTAssertFalse(state.saving)
        XCTAssertEqual(state.displayed(serverRole: .finish), .finish)
    }
    func testDelayedRoleBroadcastDoesNotUndoSuccessfulSelection() {
        var state = RoleSelection()
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
        state.succeeded(serverRole: .start)
        state.receivedServerState(serverRole: .start)
        XCTAssertEqual(state.displayed(serverRole: .start), .finish)
        state.receivedServerState(serverRole: .finish)
        XCTAssertNil(state.optimistic)
        state.receivedServerState(serverRole: .start)
        XCTAssertEqual(state.displayed(serverRole: .start), .start)
    }
    func testRapidRoleTapsCoalesceToFinalSelection() {
        var state = RoleSelection()
        XCTAssertTrue(state.begin(.finish, serverRole: .start))
        XCTAssertFalse(state.begin(.start, serverRole: .start))
        XCTAssertFalse(state.begin(.finish, serverRole: .start))
        state.succeeded(serverRole: .finish)
        XCTAssertFalse(state.saving)
        XCTAssertNil(state.optimistic)
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
        XCTAssertFalse(StageDelay(random: false, min: 11, max: 11).valid)
        XCTAssertFalse(StageDelay(random: true, min: 1.5, max: 5).valid)
        XCTAssertEqual(StageDelay(random: true, min: 1.6, max: 25).normalized, StageDelay(random: true, min: 2, max: 10))
        XCTAssertFalse(StageDelay(random: true, min: 5, max: 2).valid)
        XCTAssertFalse(StageDelay(random: false, min: .nan, max: 2).valid)
        XCTAssertFalse(StageDelay(random: false, min: 31, max: 31).valid)
        XCTAssertEqual(StageDelay(random: false, min: 5, max: 10).sample(), 5)
    }
    func testLegacyDelaySettingsMigrateToSliderBounds() {
        XCTAssertEqual(StageDelay(random: true, min: 1, max: 2).normalized, StageDelay(random: true, min: 1, max: 2))
        XCTAssertEqual(StageDelay(random: true, min: 40, max: 0).normalized, StageDelay(random: true, min: 10, max: 10))
        XCTAssertTrue(StageDelay(random: false, min: 4, max: 5).valid)
    }
    func testRangeThumbsCannotCrossOrExceedBounds() {
        var stage = StageDelay(random: true, min: 5, max: 8)
        stage.setLower(25); XCTAssertEqual(stage.min, 8)
        stage.setUpper(0); XCTAssertEqual(stage.max, 8)
        stage.setLower(-10); XCTAssertEqual(stage.min, 0)
        stage.setUpper(99); XCTAssertEqual(stage.max, 10)
        XCTAssertTrue(stage.valid)
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

final class NtpTests: XCTestCase {
    func packet(_ t: Double) -> ([UInt8],[UInt8]) {
        var request = [UInt8](repeating:0,count:48); request[0] = 0x23
        NtpPacket.write(&request,40,utcMs:t)
        var response = [UInt8](repeating:0,count:48); response[0] = 0x24; response[1] = 2
        response.replaceSubrange(24..<32,with:request[40..<48])
        NtpPacket.write(&response,32,utcMs:t+6); NtpPacket.write(&response,40,utcMs:t+7)
        return (request,response)
    }
    func testEpochAnd2036EraRollover() {
        for time in [0.0, 1_700_000_000_123.25, 2_085_978_495_999.0, 2_085_978_496_001.5, 4_000_000_000_000.0] {
            var bytes = [UInt8](repeating:0,count:48)
            NtpPacket.write(&bytes,40,utcMs:time)
            XCTAssertEqual(NtpPacket.timestamp(bytes,40,pivotMs:time),time,accuracy:0.002)
        }
    }
    func testFourTimestampsAndValidation() throws {
        let t = 1_700_000_000_000.0
        let (request,response) = packet(t)
        let sample = try NtpPacket.parse(response,request:request,t1:t,t4:t+11)
        let mapping = try ClockMapping.average([sample])
        XCTAssertEqual(mapping.offset,1,accuracy:0.002)
        XCTAssertEqual(mapping.averageRttMs,10,accuracy:0.002)
        for index in [0,1,24,32,40] {
            var invalid = response
            if index == 0 { invalid[0] = 0xe4 }
            else if index == 1 { invalid[1] = 16 }
            else if index == 24 { invalid[24] ^= 1 }
            else { invalid.replaceSubrange(index..<index+8,with:[UInt8](repeating:0,count:8)) }
            XCTAssertThrowsError(try NtpPacket.parse(invalid,request:request,t1:t,t4:t+11))
        }
        XCTAssertThrowsError(try NtpPacket.parse([0],request:request,t1:t,t4:t+11))
        var kod = response; kod[1] = 0; kod.replaceSubrange(12..<16,with:Array("RATE".utf8))
        XCTAssertThrowsError(try NtpPacket.parse(kod,request:request,t1:t,t4:t+11)) { XCTAssertTrue($0 is NtpPacket.Kiss) }
    }
    func testMappingUsesDifferenceAndFrozenSnapshot() {
        let local = MonotonicClock.now()
        var mapping = ClockMapping(offset:100,uncertaintyMs:3,averageRttMs:2,sampledAt:local/1000)
        mapping.referenceMono = MonotonicClock.nanosAt(local); mapping.referenceUTC = 1_700_000_000_000
        let locked = mapping
        mapping.referenceUTC = 9_000_000_000_000
        XCTAssertEqual(locked.utcAt(local+1234.5),1_700_000_001_234.5,accuracy:0.002)
        XCTAssertNotEqual(mapping.utcAt(local),locked.utcAt(local))
        let old = ClockMapping(offset:0,uncertaintyMs:3,averageRttMs:2,sampledAt:(local-121000)/1000)
        XCTAssertFalse(old.fresh)
        XCTAssertGreaterThan(old.estimatedUncertaintyMs,old.uncertaintyMs)
    }
    @MainActor func testTencentPreferenceFallbackAndBothUnavailable() async throws {
        for fails in [0,1,2] {
            let client = NtpClient(); client.configuration.validSamples = 3
            client.pause = { _ in }
            var hosts: [String] = []
            client.exchange = { host, _ in
                hosts.append(host)
                if fails == 2 || (fails == 1 && host == "ntp.tencent.com") { throw ClientError.message("UDP blocked") }
                return ClockSample(sent:0,received:10,serverReceived:6,serverSent:6)
            }
            do {
                let result = try await client.synchronize { _ in }
                XCTAssertLessThan(fails,2)
                XCTAssertEqual(result.server,fails == 0 ? "ntp.tencent.com" : "ntp.aliyun.com")
            } catch { XCTAssertEqual(fails,2) }
            XCTAssertEqual(hosts.first,"ntp.tencent.com")
            if fails == 0 { XCTAssertFalse(hosts.contains("ntp.aliyun.com")) }
        }
    }
}

extension NtpTests {
    @MainActor func testInvalidResponseFallbackAndRetryPolicy() async throws {
        let client=NtpClient(); client.configuration.validSamples=3; client.configuration.consecutiveFailureLimit=2
        client.pause={ _ in }
        var failures=0
        client.exchange={ server, _ in
            if server=="ntp.tencent.com" {
                failures += 1
                _ = try NtpPacket.parse([0],request:[UInt8](repeating:0,count:48),t1:0,t4:1)
            }
            return ClockSample(sent:0,received:10,serverReceived:6,serverSent:6)
        }
        let value=try await client.synchronize { _ in }
        XCTAssertEqual(value.server,"ntp.aliyun.com"); XCTAssertEqual(failures,2)
    }
    func testDriftBudgetAndInteroperableRaceVector() throws {
        let local=MonotonicClock.now()
        let tired=ClockMapping(offset:0,uncertaintyMs:24,averageRttMs:2,sampledAt:(local-30000)/1000)
        XCTAssertFalse(tired.fresh)
        let json=#"{"kind":"start","at":1700000000000.25,"uncertaintyMs":3,"monoNanos":"18446744073709550000","deviceId":"ios","sessionId":"round","syncServer":"ntp.tencent.com","syncSource":"NTP"}"#
        let event=try JSONDecoder().decode(TimingEvent.self,from:Data(json.utf8))
        XCTAssertEqual(event.monoNanos,"18446744073709550000")
        XCTAssertEqual(1700000010000.75-event.at,10000.5)
        let samples=[ClockSample](repeating:ClockSample(sent:0,received:10,serverReceived:6,serverSent:6),count:8)
        let mapping=try NtpQuality.select(samples)
        XCTAssertEqual(mapping.offset,1); XCTAssertEqual(mapping.uncertaintyMs,7.0005,accuracy:0.000001)
    }
}

extension NtpTests {
    @MainActor func testKissDenialIsNotRetriedInNextRound() async throws {
        let client=NtpClient(); client.configuration.validSamples=3; client.pause={ _ in }
        var deniedRequests=0
        client.exchange={ host, _ in
            if host=="ntp.tencent.com" { deniedRequests += 1; throw NtpPacket.Kiss(code:"DENY",poll:4) }
            return ClockSample(sent:0,received:10,serverReceived:6,serverSent:6)
        }
        _ = try await client.synchronize { _ in }
        _ = try await client.synchronize { _ in }
        XCTAssertEqual(deniedRequests,1)
    }
    func testUnstableAndSlowSamplesDoNotClaimAccuracy() {
        let slow=[ClockSample](repeating:ClockSample(sent:0,received:1000,serverReceived:500,serverSent:500),count:8)
        XCTAssertThrowsError(try NtpQuality.select(slow))
    }
}

final class AvatarTests: XCTestCase {
    func testRawSpacesBecomePercent20OnlyOnce() throws {
        for filename in ["Nike Dragonfly.png", "adidas Adizero Prime SP 2.png", "New Balance FuelCell SuperComp MD-X.png", "PUMA evoSPEED Sprint Nitro 2.png"] {
            let url=try XCTUnwrap(AvatarImageURL.make(filename))
            XCTAssertTrue(url.absoluteString.contains("%20"))
            XCTAssertFalse(url.absoluteString.contains("%2520"))
            XCTAssertEqual(url.lastPathComponent,filename)
            XCTAssertEqual(url.host,"download.runtick.cc")
        }
        XCTAssertEqual(AvatarImageURL.make("Nike Dragonfly.png")?.absoluteString,"https://download.runtick.cc/avatar/Nike%20Dragonfly.png")
    }
    func testUnexpectedPathsNeverBecomeRemoteImageURLs() {
        for value in [nil,"",".png","../Nike Dragonfly.png","Nike%20Dragonfly.png","avatar/Nike Dragonfly.png","https://evil.example/a.png"] as [String?] {
            XCTAssertNil(AvatarImageURL.make(value))
        }
    }
    func testLegacyAndCurrentUserAndMemberDecode() throws {
        let decoder=JSONDecoder()
        let legacy=try decoder.decode(User.self,from:Data(#"{"id":1,"loginId":"runner"}"#.utf8))
        XCTAssertNil(legacy.avatar)
        let user=try decoder.decode(User.self,from:Data(#"{"id":1,"loginId":"runner","avatar":"Nike Dragonfly.png"}"#.utf8))
        XCTAssertEqual(user.avatar,"Nike Dragonfly.png")
        let restored=try decoder.decode(User.self,from:JSONEncoder().encode(user))
        XCTAssertEqual(restored.avatar,user.avatar)
        let member=try decoder.decode(Member.self,from:Data(#"{"loginId":"runner","deviceRole":"start","online":true,"avatar":"Nike Dragonfly.png"}"#.utf8))
        XCTAssertEqual(member.avatar,user.avatar)
    }
}
