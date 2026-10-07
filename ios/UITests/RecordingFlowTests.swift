import XCTest

final class RecordingFlowTests: XCTestCase {
    func testBackgroundReturnStopAndPlayFromAudioLibrary() {
        defer { XCUIDevice.shared.orientation = .portrait }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AWDRecordingUITest"]
        app.launch()
        let mode = app.buttons["capture.mode.audio"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.tap()
        let shutter = app.buttons["capture.shutter"]
        shutter.tap()
        XCTAssertTrue(app.staticTexts["recording.elapsed"].waitForExistence(timeout: 5))
        let stopped = NSPredicate(format: "label == %@", "Stop recording")
        expectation(for: stopped, evaluatedWith: shutter)
        waitForExpectations(timeout: 30)
        XCUIDevice.shared.orientation = .landscapeLeft
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: shutter)
        waitForExpectations(timeout: 5)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertEqual(shutter.label, "Stop recording")
        XCTAssertTrue(shutter.isHittable)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: shutter)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(shutter.label, "Stop recording")
        XCTAssertTrue(shutter.isEnabled)
        XCTAssertTrue(shutter.isHittable)
        let elapsed = app.staticTexts["recording.elapsed"]
        XCTAssertNotEqual(elapsed.label, "00:00")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIDevice.shared.orientation = .portrait
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: shutter)
        waitForExpectations(timeout: 5)
        XCTAssertLessThan(app.frame.width, app.frame.height)
        XCTAssertEqual(shutter.label, "Stop recording")
        XCTAssertTrue(shutter.isHittable)
        shutter.tap()
        let saved = app.buttons["Recording saved · Open library to play"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        app.segmentedControls.buttons["Audio"].tap()
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.item.")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        let play = app.buttons["media.playback"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 30)
        play.tap()
        XCTAssertTrue(play.label.contains("Pause"))
        play.tap()
        XCTAssertTrue(play.label.contains("Play"))
    }
}
