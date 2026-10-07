#if DEBUG
@preconcurrency import AVFoundation
import CoreImage
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Debug artifacts stay outside EvidenceStore, Photos, and the upload queue.
enum DualFrameSnapshot {
    struct Source: Codable, Sendable {
        let cameraID: String
        let cameraType: String
        let position: String
        let width: Int32
        let height: Int32
        let rotationDegrees: Double
        let mirrored: Bool
    }

    struct Artifact: Codable {
        let fileName: String
        let sha256: String
        let role: String
    }

    struct Manifest: Codable {
        let schemaVersion: Int
        let captureKind: String
        let note: String
        let project: RelayProject?
        let deviceWallClock: Date
        let pair: DualFramePair
        let rearSource: Source
        let frontSource: Source
        let rearPixelWidth: Int
        let rearPixelHeight: Int
        let frontPixelWidth: Int
        let frontPixelHeight: Int
        let artifacts: [Artifact]
    }

    /// Core Image's extent is preserved: each independent image is the entire video frame.
    static func jpeg(_ buffer: CVPixelBuffer, context: CIContext, preview: Bool = false) throws -> Data {
        var image = CIImage(cvPixelBuffer: buffer)
        if preview {
            let scale = min(1, 400 / max(image.extent.width, image.extent.height))
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): preview ? 0.55 : 0.95]) else {
            throw SnapshotError.encoding
        }
        return data
    }

    static func save(rear: CVPixelBuffer, front: CVPixelBuffer, pair: DualFramePair,
                     project: RelayProject?, rearSource: Source, frontSource: Source,
                     wallClock: Date, context: CIContext,
                     encodeFrame: (CVPixelBuffer, CIContext) throws -> Data = { try jpeg($0, context: $1) }) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiworkdeck-dual-prototype", isDirectory: true)
            .appendingPathComponent(pair.generation.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pending = root.appendingPathComponent(pair.requestID.uuidString + ".partial", isDirectory: true)
        let complete = root.appendingPathComponent(pair.requestID.uuidString, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: complete.path),
              !FileManager.default.fileExists(atPath: pending.path) else { throw SnapshotError.existingCapture }
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: false)
        // A .partial directory is deliberately retained on failure. No completed manifest is written.
        var artifacts: [Artifact] = []
        func write(_ data: Data, name: String, role: String) throws {
            let url = pending.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            let written = try Data(contentsOf: url)
            guard written == data else { throw SnapshotError.verification }
            artifacts.append(Artifact(fileName: name, sha256: digest(written), role: role))
        }
        // Persist each acquired frame before encoding the next one or the derived composite.
        try write(encodeFrame(rear, context), name: "rear-frame.jpg", role: "rearVideoFrameSnapshot")
        try write(encodeFrame(front, context), name: "front-frame.jpg", role: "frontVideoFrameSnapshot")
        try write(composite(rear: rear, front: front, context: context),
                  name: "composite.jpg", role: "derivedSideBySideComposite")
        let manifest = Manifest(schemaVersion: 1, captureKind: "synchronizedVideoFrameSnapshots",
            note: "DEBUG ONLY. JPEG encoded from video frames; not original camera photo JPEGs. " +
                "Timestamp pairing is not proof of simultaneous exposure or verified identity. " +
                "Fixed portrait rotation; generic front/back cameras; Duo direction switching unverified.",
            project: project, deviceWallClock: wallClock, pair: pair,
            rearSource: rearSource, frontSource: frontSource,
            rearPixelWidth: CVPixelBufferGetWidth(rear), rearPixelHeight: CVPixelBufferGetHeight(rear),
            frontPixelWidth: CVPixelBufferGetWidth(front), frontPixelHeight: CVPixelBufferGetHeight(front),
            artifacts: artifacts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: pending.appendingPathComponent("manifest.json"), options: .atomic)
        try FileManager.default.moveItem(at: pending, to: complete)
        return complete
    }

    private static func composite(rear: CVPixelBuffer, front: CVPixelBuffer, context: CIContext) throws -> Data {
        let images = [CIImage(cvPixelBuffer: rear), CIImage(cvPixelBuffer: front)]
        let height = max(images[0].extent.height, images[1].extent.height)
        var x: CGFloat = 0
        var result = CIImage(color: .black)
        for image in images {
            let scale = height / image.extent.height
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let translated = scaled.transformed(by: CGAffineTransform(translationX: x, y: 0))
            result = translated.composited(over: result)
            x += scaled.extent.width
        }
        result = result.cropped(to: CGRect(x: 0, y: 0, width: x, height: height))
        guard let data = context.jpegRepresentation(of: result, colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95]) else {
            throw SnapshotError.encoding
        }
        return data
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    enum SnapshotError: Error { case encoding, verification, existingCapture }
}
#endif
