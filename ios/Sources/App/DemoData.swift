import Foundation

/// 视觉走查与 Preview 用的假数据。接后端时整块删除。
enum DemoData {
    static let project = FieldProject(
        id: "p-1",
        name: "华创科技 A 轮尽调",
        archivePath: "现场影像 / 2026-08-17"
    )

    static let tally = TransferTally(waiting: 12, moving: 3, arrived: 148)

    static let link = DesktopLink(
        isOnline: true,
        lastSyncedAt: Date().addingTimeInterval(-12),
        deviceName: "MacBook Pro"
    )

    static let recent: [CaptureItem] = {
        let spec: [(MediaKind, TransferState, Int, Double)] = [
            (.photo, .arrived, 60, 1),
            (.photo, .arrived, 120, 1),
            (.video, .moving, 240, 0.62),
            (.photo, .waiting, 300, 0),
            (.video, .waiting, 420, 0),
            (.photo, .arrived, 700, 1),
            (.video, .arrived, 1_140, 1),
            (.photo, .arrived, 1_500, 1),
            (.photo, .arrived, 1_920, 1),
            (.video, .arrived, 2_400, 1),
        ]
        return spec.enumerated().map { index, s in
            let (kind, state, ago, progress) = s
            let at = Date().addingTimeInterval(-Double(ago))
            return CaptureItem(
                id: UUID(),
                kind: kind,
                state: state,
                manifest: CaptureManifest(
                    clientMediaId: UUID(),
                    sha256: String(repeating: "0", count: 60) + String(format: "%04d", index),
                    capturedAt: at,
                    serverReceivedAt: state == .arrived ? at.addingTimeInterval(6) : nil,
                    latitude: 39.9042,
                    longitude: 116.4074,
                    horizontalAccuracy: 8,
                    deviceModel: "iPhone17,2",
                    osVersion: "26.6",
                    appVersion: "0.1.0",
                    fromCamera: true,
                    tsaToken: nil
                ),
                localURL: URL(fileURLWithPath: "/dev/null"),
                progress: progress,
                lastError: state == .failed ? "连不上服务器，检查网络后重试" : nil,
                savedToAlbum: false
            )
        }
    }()
}
