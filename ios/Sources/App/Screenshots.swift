#if DEBUG
import Foundation
import UIKit

/// 上架截图用的假状态。**整份文件只编进 Debug**——发行包里不该有演示数据，
/// 更不该有任何把相机 / 定位 / 录音换成假象的分支。
///
/// 启动参数：
/// - `-AWDScreenshotMode`：打开截图模式（免登录、假数据、不开相机与定位、不发网络请求）
/// - `-AWDScreenshotScreen <n>`：直接进第 n 屏，n 见 `docs/specs/2026-09-13-store-assets-design.md` §2
///
/// 现场照片**不进 App bundle**：截图脚本把 jpg 拷进模拟器容器的
/// `Library/Application Support/ScreenshotSeed/NN.jpg`，换素材不必重新构建。
/// 拷不进去（目录空）时缩略图退回占位色块，界面照样成立。
enum Shot {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-AWDScreenshotMode")

    /// 1...8，缺省 1。用启动参数直接跳屏，比用坐标点击稳。
    static let screen: Int = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-AWDScreenshotScreen"),
              i + 1 < args.count, let n = Int(args[i + 1]) else { return 1 }
        return n
    }()

    // MARK: - 时间

    /// 归档日期，规格 §3 钉死的那一天。界面上的「今天」全部走它，
    /// 免得水印上的真实日期与归档路径对不上。
    static let dateString = "2026-09-12"

    /// 取景水印上的时刻。固定值，两次截图不会差一秒。
    static let stampDate = date(hour: 14, minute: 7, second: 32)

    static func date(hour: Int, minute: Int, second: Int = 0, day: Int = 12) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        return Calendar.current.date(from: c) ?? Date()
    }

    // MARK: - 位置

    /// 规格要求 GPS 精度显示「±5 米」。模拟器不给真定位，也不该为了截图去弹权限框。
    static let location = (lat: 39.90423, lon: 116.40740, accuracy: 5.0)

    // MARK: - 素材

    static let seedDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ScreenshotSeed", isDirectory: true)
    }()

    /// 第 n 张现场照片（1...8，越界回绕）。文件不在就返回 nil。
    static func scene(_ n: Int) -> URL? {
        let i = ((n - 1) % 8 + 8) % 8 + 1
        let url = seedDir.appendingPathComponent(String(format: "%02d.jpg", i))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func sceneImage(_ n: Int) -> UIImage? {
        guard let url = scene(n) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - 项目

    static let project = RelayProject(deviceId: "mac-1", deviceName: "MacBook Pro",
                                      key: "hc-a", name: "华创科技 A 轮尽调")

    /// 项目选择器（第 8 屏）用。第一个是主项目，与首页 / 图集一致。
    static let projects = [
        project,
        RelayProject(deviceId: "mac-1", deviceName: "MacBook Pro", key: "hd-yc", name: "恒达制造 验厂"),
        RelayProject(deviceId: "mac-1", deviceName: "MacBook Pro", key: "ns-12", name: "南山路 12 号 工程验收"),
    ]

    static let field = FieldProject(
        id: project.id,
        name: project.name,
        archivePath: tr("archive.path", ["date": dateString])
    )

    static let link = DesktopLink(isOnline: true, lastSyncedAt: Date().addingTimeInterval(-12),
                                  deviceName: "MacBook Pro")

    /// AccountUser 不是 Sendable，存成 static let 过不了 strict concurrency，用计算属性。
    static var account: AccountUser {
        AccountUser(id: 1, username: "demo", displayName: "韩律师", avatarUrl: "", role: "USER")
    }

    /// 云端中转区用量。设置页（第 7 屏）用，避免为了一行字去打网络请求。
    static let usage = (used: Int64(1_374_389_534), quota: Int64(10_737_418_240))

    // MARK: - 影像

    /// 三种状态都要有样本，另带一条录像与一条录音（任务要求）。
    /// 分两天是为了让图集的「按日分段」在第 4 屏里看得见。
    static let items: [CaptureItem] = {
        // (媒体, 状态, 时刻, 进度, 场景图序号, 日)
        let spec: [(MediaKind, TransferState, (Int, Int), Double, Int, Int)] = [
            (.photo, .waiting,   (14, 5),  0,    1, 12),
            (.photo, .uploading, (14, 2),  0.62, 2, 12),
            (.photo, .uploaded,  (13, 47), 1,    3, 12),
            (.audio, .uploaded,  (11, 20), 1,    0, 12),
            (.photo, .arrived,   (11, 8),  1,    4, 12),
            (.video, .arrived,   (10, 32), 1,    5, 12),
            (.photo, .arrived,   (9, 41),  1,    6, 12),
            (.photo, .arrived,   (9, 12),  1,    7, 12),
            (.photo, .arrived,   (16, 30), 1,    8, 11),
            (.photo, .arrived,   (15, 12), 1,    1, 11),
            (.photo, .arrived,   (14, 48), 1,    2, 11),
            (.photo, .arrived,   (10, 5),  1,    3, 11),
        ]
        // 哈希前 12 位在队列页与查看器上都露脸，写死一组好看的十六进制，
        // 不用 UUID 拼——0000 一片看着像没算出来。
        let digests = [
            "9f3c1a77b204e8d5", "4b81de20c7a93f16", "c07a5e39418bd2f4", "2ed94c86af10b573",
            "7a15b3d8e620c94f", "b6420fa1d59e837c", "e83d7c04512ba9f6", "1c9be5738da024f1",
            "5d2078eb31c4af96", "a4f19c26d3708be5", "8b73ce5091d642af", "3e60d924bf17ca85",
        ]
        return spec.enumerated().map { i, s in
            let (kind, state, hm, progress, scene, day) = s
            let at = date(hour: hm.0, minute: hm.1, day: day)
            let head = digests[i]
            return CaptureItem(
                id: UUID(),
                kind: kind,
                state: state,
                manifest: CaptureManifest(
                    clientMediaId: UUID(),
                    sha256: head + String(repeating: "0", count: max(0, 64 - head.count)),
                    capturedAt: at,
                    serverReceivedAt: state == .arrived ? at.addingTimeInterval(7) : nil,
                    latitude: location.lat,
                    longitude: location.lon,
                    horizontalAccuracy: location.accuracy,
                    deviceModel: "iPhone17,2",
                    osVersion: "26.0",
                    appVersion: "1.1.0 (1)",
                    fromCamera: true,
                    tsaToken: nil
                ),
                localURL: Shot.scene(scene) ?? URL(fileURLWithPath: "/dev/null"),
                progress: progress,
                lastError: nil,
                savedToAlbum: false,
                project: project
            )
        }
    }()
}
#endif
