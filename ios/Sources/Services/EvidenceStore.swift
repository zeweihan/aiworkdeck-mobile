import CryptoKit
import Foundation

/// 影像与归档信息的本地仓库。
///
/// 两条硬规矩：
/// 1. **原图只写应用沙盒，绝不进系统相册。** 手机丢了、相册被翻，尽调材料不在里面。
/// 2. **落盘顺序是「先原图、再算哈希、最后写 manifest」。** manifest 存在即代表这条
///    记录完整可信；中途崩溃只会留下孤儿原图，下次启动扫掉，不会产生「有记录但没哈希」
///    的半成品。
actor EvidenceStore {
    static let shared = EvidenceStore()

    // FileManager 不是 Sendable，但 FileManager.default 是线程安全的，
    // 且这里所有调用都在本 actor 内。存成属性会让它「逃出」actor 隔离，改为每次取。
    private var fm: FileManager { .default }

    /// 沙盒里的根目录。Application Support 不进 iCloud 备份也不被系统清理，
    /// 比 Caches 稳妥——现场照片丢了不可复现。
    private lazy var root: URL = {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FieldEvidence", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        var b = base
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? b.setResourceValues(rv)
        return base
    }()

    private var mediaDir: URL { root.appendingPathComponent("media", isDirectory: true) }
    private var manifestDir: URL { root.appendingPathComponent("manifest", isDirectory: true) }

    private init() {}

    private func ensureDirs() throws {
        for d in [mediaDir, manifestDir] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    // MARK: - 写入

    /// 存一条新采集。data 是相机直出的原始字节，不做任何再压缩——
    /// 压缩会改变哈希，取证链上说不清。
    func save(
        data: Data,
        kind: MediaKind,
        capturedAt: Date,
        location: (lat: Double, lon: Double, accuracy: Double)?,
        device: DeviceFacts
    ) throws -> CaptureItem {
        try ensureDirs()

        let id = UUID()
        let ext = kind == .photo ? "jpg" : "mov"
        let url = mediaDir.appendingPathComponent("\(id.uuidString).\(ext)")

        // 1. 原图先落盘
        try data.write(to: url, options: .atomic)

        // 2. 对落盘后的文件算哈希（不是对内存里的 data）——
        //    要证明的是「磁盘上这个文件」没被改过。
        let digest = try Self.sha256(of: url)

        let manifest = CaptureManifest(
            clientMediaId: id,
            sha256: digest,
            capturedAt: capturedAt,
            serverReceivedAt: nil,
            latitude: location?.lat,
            longitude: location?.lon,
            horizontalAccuracy: location?.accuracy,
            deviceModel: device.model,
            osVersion: device.osVersion,
            appVersion: device.appVersion,
            fromCamera: true,
            tsaToken: nil
        )

        // 3. manifest 最后写。它存在 == 这条记录完整。
        let item = CaptureItem(
            id: id, kind: kind, state: .waiting,
            manifest: manifest, localURL: url, progress: 0,
            lastError: nil, savedToAlbum: false
        )
        try writeManifest(item)
        return item
    }

    func updateState(_ id: UUID, to state: TransferState, progress: Double = 0,
                     error: String? = nil) throws {
        guard var item = try? loadOne(id) else { return }
        item.state = state
        item.progress = progress
        // 成功时清掉旧的失败原因，否则界面会一直挂着上次那条已经不成立的错
        item.lastError = state == .failed ? error : nil
        try writeManifest(item)
    }

    func markSavedToAlbum(_ id: UUID) throws {
        guard var item = try? loadOne(id) else { return }
        item.savedToAlbum = true
        try writeManifest(item)
    }

    /// 桌面端确认落盘后调用：删掉本地原图，manifest 留着做本机台账。
    func purgeMedia(_ id: UUID) throws {
        guard let item = try? loadOne(id) else { return }
        try? fm.removeItem(at: item.localURL)
    }

    // MARK: - 读取

    func loadAll() throws -> [CaptureItem] {
        try ensureDirs()
        let files = (try? fm.contentsOfDirectory(at: manifestDir, includingPropertiesForKeys: nil)) ?? []
        let items = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decode(at: $0) }
        return items.sorted { $0.capturedAt > $1.capturedAt }
    }

    func tally() throws -> TransferTally {
        let all = try loadAll()
        return TransferTally(
            waiting: all.filter { $0.state == .waiting || $0.state == .failed }.count,
            // uploaded 计入「在路上」：进了中转区但还没到电脑
            moving: all.filter { $0.state == .moving || $0.state == .uploaded }.count,
            arrived: all.filter { $0.state == .arrived }.count
        )
    }

    /// 清理孤儿原图：有文件没 manifest，说明上次写到一半崩了。
    /// 这类文件没有哈希与采集环境，作为证据不成立，留着只会误导。
    func sweepOrphans() throws {
        try ensureDirs()
        let known = Set(try loadAll().map { $0.localURL.lastPathComponent })
        let files = (try? fm.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil)) ?? []
        for f in files where !known.contains(f.lastPathComponent) {
            try? fm.removeItem(at: f)
        }
    }

    // MARK: - 私有

    private func loadOne(_ id: UUID) throws -> CaptureItem? {
        let u = manifestDir.appendingPathComponent("\(id.uuidString).json")
        guard fm.fileExists(atPath: u.path) else { return nil }
        return try decode(at: u)
    }

    private func decode(at url: URL) throws -> CaptureItem {
        let row = try JSONDecoder.iso.decode(StoredRow.self, from: Data(contentsOf: url))
        let ext = row.kind == .photo ? "jpg" : "mov"
        return CaptureItem(
            id: row.manifest.clientMediaId,
            kind: row.kind,
            state: row.state,
            manifest: row.manifest,
            localURL: mediaDir.appendingPathComponent("\(row.manifest.clientMediaId.uuidString).\(ext)"),
            progress: row.progress,
            lastError: row.lastError,
            savedToAlbum: row.savedToAlbum ?? false
        )
    }

    private func writeManifest(_ item: CaptureItem) throws {
        let row = StoredRow(kind: item.kind, state: item.state, progress: item.progress,
                            manifest: item.manifest, lastError: item.lastError,
                            savedToAlbum: item.savedToAlbum)
        let u = manifestDir.appendingPathComponent("\(item.id.uuidString).json")
        try JSONEncoder.iso.encode(row).write(to: u, options: .atomic)
    }

    /// 流式分块算哈希：现场录像可以到几百 MB，整份读进内存会被系统杀掉。
    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct StoredRow: Codable {
    let kind: MediaKind
    let state: TransferState
    let progress: Double
    let manifest: CaptureManifest
    // 后加的两个字段用可选 + 默认值：老记录没有它们，解码不能因此整条失败
    var lastError: String?
    var savedToAlbum: Bool?
}

struct DeviceFacts: Sendable {
    let model: String
    let osVersion: String
    let appVersion: String
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
}
