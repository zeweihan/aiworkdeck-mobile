import Foundation

/// 一张影像在「拍摄 → 抵达电脑」这条链上的位置。
/// 这是整个 App 的主线叙事，界面上所有状态表达都从这里派生。
enum TransferState: String, Codable, Sendable, CaseIterable {
    /// 在手机上，还没开始传
    case waiting
    /// 正在上传到中转区
    case moving
    /// 桌面端已确认落盘，中转区已删除
    case arrived
    case failed

    var caption: String {
        switch self {
        case .waiting: "待传输"
        case .moving: "传输中"
        case .arrived: "已上传"
        case .failed: "失败"
        }
    }

    /// 文案刻意说「已上传」而不是「已归档」「已抵达」：
    /// 现在只保证进了项目的云端存储，**桌面端拉取那一半还没做**。
    /// 说「已抵达」会让人以为东西已经在自己电脑上了，那是假的。
    /// 等桌面端确认落盘的回执做完，再把这里改成「已抵达」。
    var whereItIs: String {
        switch self {
        case .waiting: "在手机上"
        case .moving: "在路上"
        case .arrived: "在项目里"
        case .failed: "需重试"
        }
    }
}

enum MediaKind: String, Codable, Sendable {
    case photo
    case video
}

/// 取证归档信息。
///
/// 当前做到「归档级」：时间、地点、设备、SHA-256，保证「没被改过」可自证。
/// `tsaToken` 是留给「证据级」的接口 —— 接可信时间戳时把它填上，数据结构不用动。
struct CaptureManifest: Codable, Sendable {
    /// 幂等键。弱网重传、进程被杀重启，都靠它避免产生重复文件。
    let clientMediaId: UUID
    let sha256: String
    /// 设备时钟。与 serverCapturedAt 并存，两者不一致本身就是需要记录的事实。
    let capturedAt: Date
    /// 服务端在收件时盖的时间，中转区回写
    var serverReceivedAt: Date?
    let latitude: Double?
    let longitude: Double?
    /// 定位精度（米）。没有精度的坐标在质证时说明不了问题。
    let horizontalAccuracy: Double?
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    /// 是否强制来自相机（而非相册导入）。取证的前提。
    let fromCamera: Bool
    /// 可信时间戳。当前恒为 nil，接 TSA 后填入。
    var tsaToken: String?
}

struct CaptureItem: Identifiable, Sendable {
    let id: UUID
    let kind: MediaKind
    var state: TransferState
    let manifest: CaptureManifest
    /// 应用沙盒内的原图路径。不进系统相册 —— 手机丢了、相册被翻，尽调材料不在里面。
    let localURL: URL
    /// 上传进度 0...1，仅 .moving 时有意义
    var progress: Double

    var capturedAt: Date { manifest.capturedAt }
}

/// 三个状态各有多少张。首页顶部那一行就是它。
struct TransferTally: Sendable {
    var waiting: Int
    var moving: Int
    var arrived: Int

    static let zero = TransferTally(waiting: 0, moving: 0, arrived: 0)
}

struct FieldProject: Identifiable, Sendable {
    let id: String
    let name: String
    /// 归档去向的展示文案，例如「现场影像 / 2026-08-17」
    let archivePath: String
}

/// 桌面端连接状态。
/// 桌面端是 Electron，关掉就不轮询了 —— 所以「照片自动归档」的前提是它开着。
/// 界面必须把这件事说清楚，改变不了就不要藏着。
struct DesktopLink: Sendable {
    var isOnline: Bool
    var lastSyncedAt: Date?
    var deviceName: String?
}
