import XCTest

final class RecordingNavigationTests: XCTestCase {
    @MainActor func testReturnFromFinishKeepsRoomAndCanReopenRecording() {
        let app = XCUIApplication()
        app.launchArguments = ["--finish-preview"]
        app.launch()
        let back = app.buttons["recording.return"]
        XCTAssertTrue(back.waitForExistence(timeout: 10)); back.tap()
        let resume = app.buttons["room.resumeRecording"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); XCTAssertTrue(resume.isHittable)
        XCTAssertTrue(app.buttons["退出房间"].firstMatch.exists)
        resume.tap(); XCTAssertTrue(back.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testReturnFromStarterKeepsRoom() {
        let app = XCUIApplication(); app.launchArguments = ["--starter-preview"]; app.launch()
        let back = app.buttons["recording.return"]
        XCTAssertTrue(back.waitForExistence(timeout: 10)); back.tap()
        XCTAssertTrue(app.buttons["room.resumeRecording"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["退出房间"].firstMatch.exists)
    }
    @MainActor func testRecordingLayoutInLandscapeWhenSupported() throws {
        let app = XCUIApplication(); app.launchArguments = ["--finish-preview"]; app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        guard app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height else { throw XCTSkip("iPhone uses portrait recording") }
        let back = app.buttons["recording.return"]
        XCTAssertTrue(back.waitForExistence(timeout: 5)); XCTAssertTrue(back.isHittable)
        XCTAssertTrue(app.staticTexts["按住屏幕，等待冲线"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "ipad-landscape-recording"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testLargeTextStillAllowsReturnAndResume() {
        let app = XCUIApplication()
        app.launchArguments = ["--starter-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let back = app.buttons["recording.return"]
        XCTAssertTrue(back.waitForExistence(timeout: 10)); XCTAssertTrue(back.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "large-text-starter"; attachment.lifetime = .keepAlways; add(attachment)
        back.tap()
        let resume = app.buttons["room.resumeRecording"]
        if !resume.isHittable { app.swipeUp() }
        XCTAssertTrue(resume.exists)
    }

}
