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
    func testExplicitHistoryDeletionCanClearSavedResult() throws {
        let json = "{\"id\":\"r\",\"status\":\"completed\",\"createdAt\":1,\"startAt\":10,\"finishAt\":20,\"startUserId\":1,\"finishUserId\":2}"
        var saved = try JSONDecoder().decode(Race.self, from: Data(json.utf8))
        saved.savedResult = SavedResult(distance: 100, isPb: true, pbImprovementMs: nil)
        var deleted = saved
        deleted.savedResult = nil
        XCTAssertFalse(saved.accepts(deleted))
        deleted.discarded = true
        deleted = try JSONDecoder().decode(Race.self, from: JSONEncoder().encode(deleted))
        XCTAssertTrue(saved.accepts(deleted))
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

extension NtpTests {
    @MainActor func testRoomJoiningStartupSyncReceivesProgressAndRequestDetails() async throws {
        let client = NtpClient(); client.configuration.validSamples = 3
        client.pause = { _ in }
        var requests = 0
        var gate: CheckedContinuation<Void, Never>?
        client.exchange = { _, _ in
            requests += 1
            if requests == 2 { await withCheckedContinuation { gate = $0 } }
            return ClockSample(sent: 0, received: 10, serverReceived: 6, serverSent: 6)
        }
        // Startup owns the request; the room joins after the first valid sample.
        let startup = Task { try await client.synchronize { _ in } }
        while gate == nil { await Task.yield() }
        var progress: [Int] = [], details: [String] = []
        let room = Task {
            try await client.synchronize(detail: { details.append($0) }) { progress.append($0) }
        }
        while progress.isEmpty { await Task.yield() }
        XCTAssertEqual(progress.first, 1, "A late observer must receive the existing sample count")
        gate?.resume()
        let first = try await startup.value, second = try await room.value
        XCTAssertEqual(first.referenceUTC, second.referenceUTC)
        XCTAssertEqual(requests, 3, "Joining the shared task must not create more UDP requests")
        XCTAssertEqual(progress.last, 3)
        XCTAssertTrue(details.contains { $0.contains("有效响应") })
        XCTAssertTrue(details.contains { $0.contains("校时完成") })
    }

    @MainActor func testRejectedAndFailedRequestsAreVisibleEvenWithZeroValidSamples() async {
        let client = NtpClient(); client.configuration.maxAttempts = 8
        client.pause = { _ in }
        var details: [String] = [], requests = 0
        client.exchange = { server, _ in
            requests += 1
            if server == "ntp.tencent.com" { throw ClientError.message("NTP 请求超时") }
            return ClockSample(sent: 0, received: 200, serverReceived: 100, serverSent: 100)
        }
        do {
            _ = try await client.synchronize(detail: { details.append($0) }) { count in XCTAssertEqual(count, 0) }
            XCTFail("Rejected samples must not produce a mapping")
        } catch {
            XCTAssertNil(client.latest)
            XCTAssertEqual(requests, 9)
            XCTAssertTrue(details.contains { $0.contains("ntp.tencent.com") && $0.contains("请求超时") })
            XCTAssertTrue(details.contains { $0.contains("RTT") && $0.contains("未计入") })
            XCTAssertTrue(details.last?.contains("NTP 校时失败") == true)
        }
    }
}

final class SuningTimeTests: XCTestCase {
    func testProvidedResponseRequiresSuccessfulMillisecondTimestamp() throws {
        let data = Data(#"{"api":"time","code":"1","currentTime":1792384756200,"msg":""}"#.utf8)
        XCTAssertEqual(try SuningTimeProtocol.timestamp(data,status:200),1792384756200)
        for json in [#"{"api":"time","code":"0","currentTime":1792384756200}"#,
                     #"{"api":"time","code":"1","currentTime":1792384756}"#,
                     #"{"api":"time","code":"1","sysTime2":"2026-10-19 12:00:00"}"#,
                     #"{"api":"other","code":"1","currentTime":1792384756200}"#] {
            XCTAssertThrowsError(try SuningTimeProtocol.timestamp(Data(json.utf8),status:200))
        }
        XCTAssertThrowsError(try SuningTimeProtocol.timestamp(data,status:503))
        XCTAssertThrowsError(try SuningTimeProtocol.timestamp(data,status:200,age:"10"))
        XCTAssertNoThrow(try SuningTimeProtocol.timestamp(data,status:200,age:"0"))
    }
    func testMidpointOffsetMappingAndHTTPSourceMatchAndroidVector() throws {
        let t = 1792384756000.0
        let samples = (0..<4).map { n in HTTPTimeSample(sent:t+Double(n)*100,received:t+Double(n)*100+10,serverUTC:t+Double(n)*100+205) }
        var config=SuningTimeConfiguration(); config.validSamples=4
        let mapping = try SuningTimeProtocol.select(samples,config:config)
        XCTAssertEqual(mapping.offset,200)
        XCTAssertEqual(mapping.averageRttMs,10)
        XCTAssertEqual(mapping.uncertaintyMs,30.0155,accuracy:0.00001)
        XCTAssertEqual(mapping.server,"f.m.suning.com"); XCTAssertEqual(mapping.syncSource,"HTTP")
        XCTAssertEqual(mapping.validSamples,4); XCTAssertTrue(mapping.fresh)
        let local = MonotonicClock.now()
        let locked = mapping
        XCTAssertEqual(locked.utcAt(local+1234.5)-locked.utcAt(local),1234.5,accuracy:0.002)
    }
    func testInvalidSlowAndUnstableSamplesRejected() {
        let good = HTTPTimeSample(sent:0,received:10,serverUTC:205)
        XCTAssertThrowsError(try SuningTimeProtocol.select([good],config:SuningTimeConfiguration()))
        XCTAssertThrowsError(try SuningTimeProtocol.select(Array(repeating:HTTPTimeSample(sent:0,received:500,serverUTC:205),count:4),config:SuningTimeConfiguration()))
        XCTAssertThrowsError(try SuningTimeProtocol.select([good,good,good,HTTPTimeSample(sent:0,received:10,serverUTC:405)],config:SuningTimeConfiguration()))
    }
    @MainActor func testEightSamplesCacheAndFailureKeepLastValidMapping() async throws {
        let client = SuningTimeClient(); client.pause = { _ in XCTFail("Zero interval must not schedule a pause") }
        let t = MonotonicClock.now(); var count = 0
        client.exchange = {
            count += 1
            let sent = t+Double(count)*100
            return HTTPTimeSample(sent:sent,received:sent+10,serverUTC:sent+205)
        }
        let value = try await client.synchronize()
        XCTAssertEqual(count,8)
        _ = try await client.synchronize(); XCTAssertEqual(count,8)
        client.invalidate()
        var outcomes: [String] = []
        client.exchange = { count += 1; throw ClientError.message("HTTP 请求超时") }
        do { _ = try await client.synchronize(detail:{outcomes.append($0)}); XCTFail() } catch {}
        XCTAssertEqual(count,20)
        XCTAssertEqual(client.latest?.referenceUTC,value.referenceUTC)
        XCTAssertTrue(outcomes.contains { $0.contains("HTTP 请求超时") })
        var old = value; old.maximumAgeMs = -1
        XCTAssertFalse(old.fresh)
    }
    @MainActor func testLateSubscriberReceivesSharedHTTPProgress() async throws {
        let client = SuningTimeClient(); client.pause = { _ in XCTFail("Zero interval must not schedule a pause") }
        var count=0; var gate: CheckedContinuation<Void,Never>?
        let t=MonotonicClock.now()
        client.exchange = {
            count += 1
            if count==2 { await withCheckedContinuation { gate=$0 } }
            let sent=t+Double(count)*100
            return HTTPTimeSample(sent:sent,received:sent+10,serverUTC:sent+205)
        }
        let startup=Task { try await client.synchronize() }
        while gate==nil { await Task.yield() }
        var counts: [Int]=[]
        let room=Task { try await client.synchronize(progress:{counts.append($0)}) }
        while counts.isEmpty { await Task.yield() }
        XCTAssertEqual(counts.first,1)
        gate?.resume()
        _ = try await startup.value; _ = try await room.value
        XCTAssertEqual(count,8); XCTAssertEqual(counts.last,8)
        XCTAssertEqual(AppTimeSync.source,.suningHTTP)
    }
}

private final class SuningProtocolStub: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data, [String:String]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data, headers) = try Self.handler!(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:headers)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
extension SuningTimeTests {
    @MainActor func testHTTPTransportUsesNonceNoCacheAndNoAPICookies() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SuningProtocolStub.self]
        let client = SuningTimeClient(configuration:configuration)
        client.pause = { _ in }
        var nonces = Set<String>()
        SuningProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.host,"f.m.suning.com")
            XCTAssertEqual(request.url?.scheme,"https")
            XCTAssertNil(request.value(forHTTPHeaderField:"Cookie"))
            XCTAssertEqual(request.value(forHTTPHeaderField:"Cache-Control"),"no-cache, no-store")
            XCTAssertEqual(request.timeoutInterval,1.5)
            let nonce = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first { $0.name=="_runtick" }!.value!
            XCTAssertTrue(nonces.insert(nonce).inserted)
            let timestamp = Int64(MonotonicClock.now()) + Int64(nonces.count)
            return (200,Data("{\"api\":\"time\",\"code\":\"1\",\"currentTime\":\(timestamp)}".utf8),["Age":"0"])
        }
        defer { SuningProtocolStub.handler = nil }
        let value = try await client.synchronize()
        XCTAssertEqual(value.validSamples,8); XCTAssertEqual(nonces.count,8)
    }
}

extension SuningTimeTests {
    func testEightSamplesPreferLowRTTHalfInsteadOfAveragingAllOffsets() throws {
        let samples = (0..<8).map { n -> HTTPTimeSample in
            let sent=1792384756000.0+Double(n)*100
            let rtt=n<4 ? 10.0 : 100.0
            let offset=n<4 ? 200.0 : 220.0
            return HTTPTimeSample(sent:sent,received:sent+rtt,serverUTC:sent+rtt/2+offset)
        }
        let result=try SuningTimeProtocol.select(samples,config:SuningTimeConfiguration())
        XCTAssertEqual(result.validSamples,8)
        XCTAssertEqual(result.offset,200)
        XCTAssertEqual(result.averageRttMs,10)
    }
    func testRetryAfterSecondsDateAndDefault() {
        XCTAssertEqual(SuningTimeProtocol.retryDelayMs(status:429,retryAfter:"15"),15000)
        XCTAssertEqual(SuningTimeProtocol.retryDelayMs(status:503,retryAfter:"Thu, 01 Jan 1970 00:00:10 GMT",now:Date(timeIntervalSince1970:0)),10000)
        XCTAssertEqual(SuningTimeProtocol.retryDelayMs(status:429,retryAfter:"invalid"),60000)
        XCTAssertNil(SuningTimeProtocol.retryDelayMs(status:200,retryAfter:"15"))
    }
    @MainActor func testRateLimitStopsRoundAndBlocksImmediateRetry() async {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.protocolClasses=[SuningProtocolStub.self]
        let client=SuningTimeClient(configuration:configuration)
        var requests=0
        SuningProtocolStub.handler={ _ in
            requests += 1
            return (429,Data(),["Retry-After":"60"])
        }
        defer { SuningProtocolStub.handler=nil }
        for _ in 0..<2 {
            do { _ = try await client.synchronize(); XCTFail("Rate limiting must not be ignored") }
            catch { XCTAssertTrue(error is HTTPTimeRateLimit) }
        }
        XCTAssertEqual(requests,1)
        XCTAssertNil(client.latest)
    }
}
