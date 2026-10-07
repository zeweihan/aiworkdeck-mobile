#if DEBUG
import CoreImage
import CoreVideo
import CryptoKit
import ImageIO
import XCTest
@testable import Workdeck

final class DualFrameSnapshotTests: XCTestCase {
    private let generation = UUID()
    private let requestID = UUID()
    private let context = CIContext(options: [.useSoftwareRenderer: true])
    private let project = RelayProject(deviceId: "synthetic-desktop", deviceName: "Synthetic device",
                                       key: "test-project", name: "Synthetic project")

    private var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("aiworkdeck-dual-prototype")
            .appendingPathComponent(generation.uuidString)
    }

    override func tearDownWithError() throws {
        // This UUID belongs only to this test instance, never to real diagnostic captures.
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    private var pair: DualFramePair {
        let rear = DualFrameStamp(ptsValue: 100100, ptsTimescale: 1000, ptsEpoch: 0,
                                  hostSeconds: 100.1, dropped: false)
        let front = DualFrameStamp(ptsValue: 100110, ptsTimescale: 1000, ptsEpoch: 0,
                                   hostSeconds: 100.11, dropped: false)
        return DualFramePair(requestID: requestID, generation: generation, requestedAtHostSeconds: 100,
            acceptedAtHostSeconds: 100.2, rear: rear, front: front,
            maximumSkewSeconds: 0.035, maximumAgeSeconds: 0.25)
    }

    private func source(front: Bool) -> DualFrameSnapshot.Source {
        DualFrameSnapshot.Source(cameraID: front ? "synthetic-front" : "synthetic-rear",
            cameraType: "synthetic", position: front ? "front" : "back",
            width: front ? 6 : 4, height: front ? 4 : 6, rotationDegrees: 90, mirrored: false)
    }

    private func buffer(width: Int, height: Int, red: UInt8) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                        attributes as CFDictionary, &result)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(result)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            for column in 0..<width {
                let offset = row * stride + column * 4
                address[offset] = 30
                address[offset + 1] = 80
                address[offset + 2] = red
                address[offset + 3] = 255
            }
        }
        return buffer
    }

    private func save(encodeFrame: (CVPixelBuffer, CIContext) throws -> Data = {
        try DualFrameSnapshot.jpeg($0, context: $1)
    }) throws -> URL {
        try DualFrameSnapshot.save(rear: buffer(width: 4, height: 6, red: 200),
            front: buffer(width: 6, height: 4, red: 40), pair: pair, project: project,
            rearSource: source(front: false), frontSource: source(front: true),
            wallClock: Date(timeIntervalSince1970: 1_700_000_000), context: context,
            encodeFrame: encodeFrame)
    }

    func testSavesThreeImagesWithVerifiedHashesAndLockedProject() throws {
        let folder = try save()
        XCTAssertEqual(folder, root.appendingPathComponent(requestID.uuidString, isDirectory: true))
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        XCTAssertEqual(names, ["rear-frame.jpg", "front-frame.jpg", "composite.jpg", "manifest.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(requestID.uuidString + ".partial").path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(DualFrameSnapshot.Manifest.self,
            from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        XCTAssertEqual(manifest.project, project)
        XCTAssertEqual(manifest.pair, pair)
        XCTAssertEqual(manifest.captureKind, "synchronizedVideoFrameSnapshots")
        XCTAssertTrue(manifest.note.contains("not original camera photo JPEGs"))
        XCTAssertEqual(manifest.rearPixelWidth, 4)
        XCTAssertEqual(manifest.rearPixelHeight, 6)
        XCTAssertEqual(manifest.frontPixelWidth, 6)
        XCTAssertEqual(manifest.frontPixelHeight, 4)
        XCTAssertEqual(manifest.rearSource.cameraID, "synthetic-rear")
        XCTAssertEqual(manifest.frontSource.cameraID, "synthetic-front")
        XCTAssertEqual(manifest.artifacts.count, 3)
        for artifact in manifest.artifacts {
            let data = try Data(contentsOf: folder.appendingPathComponent(artifact.fileName))
            XCTAssertEqual(artifact.sha256, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let expected: (Int, Int) = switch artifact.fileName {
            case "rear-frame.jpg": (4, 6)
            case "front-frame.jpg": (6, 4)
            default: (13, 6)
            }
            XCTAssertEqual(image.width, expected.0)
            XCTAssertEqual(image.height, expected.1)
        }
    }

    func testDuplicateCaptureDoesNotOverwriteCompletedGroup() throws {
        let folder = try save()
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let original = try names.map { try Data(contentsOf: folder.appendingPathComponent($0)) }
        var calledEncoder = false
        XCTAssertThrowsError(try save { _, _ in calledEncoder = true; return Data() }) { error in
            guard case DualFrameSnapshot.SnapshotError.existingCapture = error else {
                return XCTFail("Unexpected duplicate error: \(error)")
            }
        }
        XCTAssertFalse(calledEncoder)
        XCTAssertEqual(try names.map { try Data(contentsOf: folder.appendingPathComponent($0)) }, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(requestID.uuidString + ".partial").path))
    }

    func testSecondFrameEncodingFailurePreservesFirstFrameWithoutCompletedManifest() throws {
        enum Injected: Error { case secondFrame }
        var encoded = 0
        XCTAssertThrowsError(try save { buffer, context in
            encoded += 1
            if encoded == 2 { throw Injected.secondFrame }
            return try DualFrameSnapshot.jpeg(buffer, context: context)
        }) { error in
            guard case Injected.secondFrame = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let pending = root.appendingPathComponent(requestID.uuidString + ".partial")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: pending.path), ["rear-frame.jpg"])
        let data = try Data(contentsOf: pending.appendingPathComponent("rear-frame.jpg"))
        XCTAssertNotNil(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(requestID.uuidString).path))
        XCTAssertThrowsError(try save()) // Retrying the same ID must not overwrite this retained draft either.
        XCTAssertEqual(try Data(contentsOf: pending.appendingPathComponent("rear-frame.jpg")), data)
    }
}
#endif
