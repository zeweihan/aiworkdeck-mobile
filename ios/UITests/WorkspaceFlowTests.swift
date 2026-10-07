import XCTest

final class WorkspaceFlowTests: XCTestCase {
    @MainActor
    func testLandscapeFilesAtAccessibilityTextSize() {
        defer { XCUIDevice.shared.orientation = .portrait }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-AWDWorkspaceUITest", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let alpha = app.buttons["workspace.project.alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 10)); alpha.tap()
        let file = app.buttons["workspace.file.1"]
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        XCTAssertTrue(file.isHittable)
        XCTAssertTrue(app.buttons["workspace.capture"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Landscape accessibility text"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testProjectFilesQuotePreviewAndRotationContinuity() {
        defer { XCUIDevice.shared.orientation = .portrait }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AWDWorkspaceUITest"]
        app.launch()
        let alpha = app.buttons["workspace.project.alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 10))
        alpha.tap()
        let search = app.textFields["workspace.fileSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("document-12")
        let file = app.buttons["workspace.file.12"]
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "document-12")
        let wideShot = XCTAttachment(screenshot: app.screenshot()); wideShot.name = "Workspace landscape"; wideShot.lifetime = .keepAlways; add(wideShot)
        file.tap()
        let confirm = app.buttons["workspace.confirmDownload"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["workspace.preview"].exists)
        confirm.tap()
        XCTAssertTrue(app.otherElements["workspace.preview"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "document-12")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testLateProjectResponseDoesNotReplaceCurrentFiles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AWDWorkspaceUITest", "-AWDWorkspaceDelayed"]
        app.launch()
        let alpha = app.buttons["workspace.project.alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 10)); alpha.tap()
        XCTAssertTrue(app.textFields["workspace.fileSearch"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let beta = app.buttons["workspace.project.beta"]
        XCTAssertTrue(beta.waitForExistence(timeout: 5)); beta.tap()
        XCTAssertTrue(app.staticTexts["beta-document-1.pdf"].waitForExistence(timeout: 5))
        // Allow the cancelled Alpha response to arrive after Beta has rendered.
        let late = expectation(description: "late LIST delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { late.fulfill() }
        wait(for: [late], timeout: 12)
        XCTAssertTrue(app.staticTexts["beta-document-1.pdf"].exists)
        XCTAssertFalse(app.staticTexts["alpha-document-1.pdf"].exists)
    }

    @MainActor
    func testOfflineFilesStillOfferLocalRecords() {
        let app = XCUIApplication()
        app.launchArguments = ["-AWDWorkspaceUITest", "-AWDWorkspaceOffline"]
        app.launch()
        let alpha = app.buttons["workspace.project.alpha"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 10)); alpha.tap()
        XCTAssertTrue(app.staticTexts["Test desktop is offline"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Field records"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Audio"].waitForExistence(timeout: 5))
    }
}
