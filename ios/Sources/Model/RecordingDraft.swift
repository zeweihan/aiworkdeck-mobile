import Foundation

/// Durable start metadata accompanies the audio until EvidenceStore commits it.
struct RecordingDraft: Codable {
    let id: UUID
    let startedAt: Date
    let project: RelayProject?
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?
    let device: DeviceFacts

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecordingDrafts", isDirectory: true)
    }
    var audioURL: URL { Self.directory.appendingPathComponent("\(id).m4a") }
    var metadataURL: URL { Self.directory.appendingPathComponent("\(id).json") }
    var location: (lat: Double, lon: Double, accuracy: Double)? {
        guard let latitude, let longitude, let accuracy else { return nil }
        return (latitude, longitude, accuracy)
    }

    func persist() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        var dir = Self.directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dir.setResourceValues(values)
        try JSONEncoder.iso.encode(self).write(to: metadataURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove() {
        try? FileManager.default.removeItem(at: audioURL)
        try? FileManager.default.removeItem(at: metadataURL)
    }

    static func pending() throws -> [RecordingDraft] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder.iso.decode(Self.self, from: Data(contentsOf: $0)) }
    }
}
