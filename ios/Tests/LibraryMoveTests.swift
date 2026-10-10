import XCTest
@testable import Workdeck

final class LibraryMoveTests: XCTestCase {
    private let a = RelayProject(deviceId: "device-a", deviceName: "Desktop", key: "7", name: "Same name")
    private let b = RelayProject(deviceId: "device-b", deviceName: "Desktop", key: "7", name: "Same name")

    func testUnassignedCaptureWaitsForExplicitMoveAndPreservesOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EvidenceStore(root: root)
        for kind in [MediaKind.audio, .photo] {
            let bytes = Data([7, 8, 9])
            let item = try await store.save(data: bytes, kind: kind, capturedAt: Date(timeIntervalSince1970: 100),
                                           location: nil, device: DeviceFacts(model: "test", osVersion: "test", appVersion: "test"), project: nil)
            let unassigned = try await store.claimNextUpload()
            XCTAssertNil(unassigned)
            try await store.moveToProject(item.id, a)
            try await store.moveToProject(item.id, b)
            let restored = try await EvidenceStore(root: root).loadAll()
            let moved = try XCTUnwrap(restored.first { $0.id == item.id })
            XCTAssertEqual(moved.projectID, b.id)
            XCTAssertNotEqual(moved.projectID, a.id)
            XCTAssertEqual(moved.manifest.sha256, item.manifest.sha256)
            XCTAssertEqual(moved.capturedAt, item.capturedAt)
            XCTAssertEqual(moved.manifest.clientMediaId, item.manifest.clientMediaId)
            XCTAssertEqual(try Data(contentsOf: moved.localURL), bytes)
            let claimed = try await store.claimNextUpload()
            XCTAssertEqual(claimed?.projectID, b.id)
            XCTAssertEqual(claimed?.state, .uploading)
            await store.delete(ids: [item.id])
        }
    }

    func testLegacyUnassignedRecordsCanMoveButAssignedReceiptsStayBound() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EvidenceStore(root: root)
        for project in [nil, a] {
            let item = try await store.save(data: Data([2]), kind: .photo, capturedAt: Date(), location: nil,
                                           device: DeviceFacts(model: "test", osVersion: "test", appVersion: "test"), project: project)
            let manifest = root.appendingPathComponent("manifest/\(item.id.uuidString).json")
            var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
            legacy.removeValue(forKey: "uploadAttempted")
            try JSONSerialization.data(withJSONObject: legacy).write(to: manifest)
            let loaded = try await store.loadAll()
            let restored = try XCTUnwrap(loaded.first { $0.id == item.id })
            XCTAssertEqual(restored.canMoveToProject, project == nil)
            if project == nil { try await store.moveToProject(item.id, b) }
        }
    }

    func testUploadClaimPreventsMoveEvenAfterFailureOrRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EvidenceStore(root: root)
        let item = try await store.save(data: Data([1]), kind: .audio, capturedAt: Date(), location: nil,
                                       device: DeviceFacts(model: "test", osVersion: "test", appVersion: "test"), project: a)
        _ = try await store.claimNextUpload()
        for state in [TransferState.uploading, .uploaded, .arrived, .failed, .waiting] {
            try await store.updateState(item.id, to: state)
            do {
                try await EvidenceStore(root: root).moveToProject(item.id, b)
                XCTFail("An attempted upload must retain its destination: \(state)")
            } catch {}
            let restored = try await store.loadAll()
            XCTAssertEqual(restored.first?.projectID, a.id)
            XCTAssertEqual(restored.first?.state, state)
        }
    }
}
