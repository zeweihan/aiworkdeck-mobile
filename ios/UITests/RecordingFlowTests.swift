import XCTest

final class RecordingFlowTests: XCTestCase {
    func testBackgroundReturnStopAndPlayFromAudioLibrary() {
        continueAfterFailure = false
        let app = XCUIApplication()
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
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()
        XCTAssertEqual(shutter.label, "Stop recording")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(shutter.isEnabled)
        XCTAssertTrue(shutter.isHittable)
        let elapsed = app.staticTexts["recording.elapsed"]
        XCTAssertNotEqual(elapsed.label, "00:00")
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
