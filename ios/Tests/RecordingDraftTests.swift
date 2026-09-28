import XCTest
@testable import Workdeck

final class RecordingDraftTests: XCTestCase {
    func testDraftSurvivesRestartAndCommitIsIdempotent() async throws {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let draft = RecordingDraft(id: UUID(), startedAt: date, project: nil,
                                   latitude: 1, longitude: 2, accuracy: 3,
                                   device: DeviceFacts(model: "test", osVersion: "test", appVersion: "test"))
        defer { draft.remove() }
        try draft.persist()
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: draft.audioURL)
        let recovered = try XCTUnwrap(RecordingDraft.pending().first { $0.id == draft.id })
        XCTAssertEqual(recovered.startedAt, date)
        XCTAssertEqual(recovered.location?.lat, 1)
        let first = try await EvidenceStore.shared.saveRecording(recovered)
        let second = try await EvidenceStore.shared.saveRecording(recovered)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.kind, .audio)
        XCTAssertEqual(first.state, .waiting)
        XCTAssertEqual(first.capturedAt, date)
        XCTAssertEqual(try Data(contentsOf: first.localURL), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: draft.audioURL.path))
        draft.remove()
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.localURL.path))
        await EvidenceStore.shared.delete(ids: [first.id])
    }

    func testMissingAudioDoesNotDiscardRecoveryMetadata() async throws {
        let draft = RecordingDraft(id: UUID(), startedAt: Date(), project: nil,
                                   latitude: nil, longitude: nil, accuracy: nil,
                                   device: DeviceFacts(model: "test", osVersion: "test", appVersion: "test"))
        defer { draft.remove() }
        try draft.persist()
        do {
            _ = try await EvidenceStore.shared.saveRecording(draft)
            XCTFail("Missing audio must fail")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: draft.metadataURL.path))
        }
    }
}
