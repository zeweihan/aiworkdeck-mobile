import XCTest
@testable import Workdeck

final class TransferPhaseTests: XCTestCase {
    func testPhaseMapping() {
        XCTAssertEqual(TransferState.waiting.phase, .uploading)
        XCTAssertEqual(TransferState.uploading.phase, .uploading)
        XCTAssertEqual(TransferState.failed.phase, .uploading)
        XCTAssertEqual(TransferState.uploaded.phase, .staged)
        XCTAssertEqual(TransferState.arrived.phase, .landed)
    }

    func testCaptions() {
        XCTAssertEqual(TransferPhase.uploading.caption, "上传中")
        XCTAssertEqual(TransferPhase.staged.caption, "已暂存")
        XCTAssertEqual(TransferPhase.landed.caption, "已落盘")
        XCTAssertEqual(TransferState.failed.caption, "上传失败")
        XCTAssertEqual(TransferState.waiting.caption, "上传中")
        // caption 是短形式（state.uploaded），长句「已暂存 · 等待桌面端接收」在 detail 里。
        XCTAssertEqual(TransferState.uploaded.caption, "已暂存")
        XCTAssertEqual(TransferState.uploaded.detail, "已暂存 · 等待桌面端接收")
        XCTAssertEqual(TransferState.arrived.caption, "已落盘")
    }

    func testTallyCountsFailedInsideUploading() {
        let items = [
            TestItems.make(.waiting), TestItems.make(.failed), TestItems.make(.uploading),
            TestItems.make(.uploaded), TestItems.make(.arrived), TestItems.make(.arrived),
        ]
        let t = TransferTally.of(items)
        XCTAssertEqual(t.uploading, 3)
        XCTAssertEqual(t.failed, 1)
        XCTAssertEqual(t.staged, 1)
        XCTAssertEqual(t.landed, 2)
        XCTAssertEqual(t.total, 6)
    }
}

/// 测试用造件。project 与时间可指定，其余字段无关紧要。
enum TestItems {
    static func make(_ state: TransferState, project: RelayProject? = nil,
                     at: Date = Date(), kind: MediaKind = .photo) -> CaptureItem {
        let id = UUID()
        return CaptureItem(
            id: id, kind: kind, state: state,
            manifest: CaptureManifest(
                clientMediaId: id, sha256: String(repeating: "a", count: 64),
                capturedAt: at, serverReceivedAt: nil, latitude: nil, longitude: nil,
                horizontalAccuracy: nil, deviceModel: "x", osVersion: "x", appVersion: "x",
                fromCamera: true, tsaToken: nil),
            localURL: URL(fileURLWithPath: "/dev/null"), progress: 0,
            lastError: nil, savedToAlbum: false, project: project)
    }
}
