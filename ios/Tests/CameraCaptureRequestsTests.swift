import XCTest
@testable import Workdeck

final class CameraCaptureRequestsTests: XCTestCase {
    @MainActor
    func testDelayedPhotoUsesShutterOwnerAfterUIChanges() {
        var requests = CameraCaptureRequests()
        var delivered: [String] = []
        var uiCallback: ((Data, MediaKind, Date) -> Void)? = { _, _, _ in delivered.append("project-A") }
        let at = Date(timeIntervalSince1970: 123)
        requests.begin(id: 1, at: at, completed: uiCallback, failed: nil)
        uiCallback = { _, _, _ in delivered.append("project-B") }
        requests.begin(id: 2, at: at, completed: uiCallback, failed: nil)
        let lateA = requests.take(id: 1)
        XCTAssertEqual(lateA?.capturedAt, at)
        lateA?.completed?(Data([1]), .photo, lateA!.capturedAt)
        let b = requests.take(id: 2)
        b?.completed?(Data([2]), .photo, at)
        XCTAssertEqual(delivered, ["project-A", "project-B"])
        XCTAssertNil(requests.take(id: 1))
        XCTAssertTrue(requests.isEmpty)
    }

    func testStopRejectsPermissionOrConfigurationCompletion() {
        var intent = CameraStartIntent()
        let beforePermission = intent.begin()
        intent.stop()
        XCTAssertFalse(intent.accepts(beforePermission))
        let newRequest = intent.begin()
        XCTAssertFalse(intent.accepts(beforePermission))
        XCTAssertTrue(intent.accepts(newRequest))
        intent.stop()
        XCTAssertFalse(intent.accepts(newRequest))
    }
}
