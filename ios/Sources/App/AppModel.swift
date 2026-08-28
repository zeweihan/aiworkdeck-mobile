import Foundation
import SwiftUI

/// 全局状态。界面只读它，写入一律经过这里，保证 store 与 UI 不会各说各话。
@MainActor
@Observable
final class AppModel {
    // 用 AppModel.today 而不是 Self.today：类的存储属性初始化式里不能引用
    // 协变的 Self，编译器直接拒。
    var project = FieldProject(
        id: "local",
        name: "未选择项目",
        archivePath: "现场影像 / \(AppModel.today)"
    )
    var items: [CaptureItem] = []
    var tally: TransferTally = .zero
    /// 桌面端连接。还没做配对，先恒定离线——**不要为了界面好看假装在线**，
    /// 那会让人以为照片已经在往电脑走。
    var link = DesktopLink(isOnline: false, lastSyncedAt: nil, deviceName: nil)

    /// 当前账号。nil = 未登录，界面走登录页。
    var account: AccountUser?
    var isSignedIn: Bool { account != nil }
    /// 启动时先按 Keychain 里有没有会话决定初屏，避免登录页闪一下再跳走。
    private(set) var didRestore = false

    static var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - 账号

    /// 选中的归档目标。nil = 还没选，界面走项目选择页。
    /// 存 UserDefaults 就够——项目条目不是凭据，泄露它没有意义。
    /// （旧版存的是 Int 型云端项目 id，键 selectedProjectId；目录镜像的 key 是
    /// 桌面机本地 id，两个命名空间不通，升级后旧选择一律作废、回到选择页。）
    var selectedProject: RelayProject? {
        didSet {
            if let p = selectedProject, let data = try? JSONEncoder().encode(p) {
                UserDefaults.standard.set(data, forKey: "selectedRelayProject")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedRelayProject")
            }
        }
    }

    func didLogin(_ result: LoginResult) async {
        account = result.user
        await refresh()
    }

    func selectProject(_ p: RelayProject) async {
        selectedProject = p
        project = FieldProject(id: p.id, name: p.name,
                               archivePath: "现场影像 / \(AppModel.today)")
        await UploadQueue.shared.configure(project: p) { [weak self] in
            await self?.refresh()
        }
        await UploadQueue.shared.kick()
    }

    /// 拍完立刻踢一脚队列。不等用户手动点上传——现场没人会记得点。
    func kickUpload() {
        Task { await UploadQueue.shared.kick() }
    }

    func retryFailedUploads() {
        Task { await UploadQueue.shared.retryFailed() }
    }

    /// 单条重试。队列页每行都有，不用为了一条失败去点「全部重试」。
    func retry(_ item: CaptureItem) {
        Task {
            try? await EvidenceStore.shared.updateState(item.id, to: .waiting, progress: 0)
            await refresh()
            await UploadQueue.shared.kick()
        }
    }

    /// 切项目：清掉选择回到选择页。不动已拍的影像，它们仍属于原项目的队列。
    func clearProjectSelection() {
        selectedProject = nil
    }

    /// 未投递件的中转区到期时刻（键 clientMediaId 小写）。队列页做到期提醒用。
    var cloudExpiry: [String: Date] = [:]

    /// 查投递回执：停在中转区的影像被桌面端取走后改成「已抵达」。
    func checkDelivered() {
        Task {
            cloudExpiry = await UploadQueue.shared.checkDelivered()
            await refresh()
        }
    }

    func signOut() {
        API.shared.logout()
        account = nil
        // **不清本地影像。** 退出登录不等于放弃已经拍到的东西——
        // 现场是不可复现的，登出就删是灾难性的默认。
    }

    func refresh() async {
        do {
            let all = try await EvidenceStore.shared.loadAll()
            let t = try await EvidenceStore.shared.tally()
            items = all
            tally = t
        } catch {
            // 读不出来不该清空界面——宁可显示上一次的状态，也不要让用户以为照片没了
        }
    }

    func bootstrap() async {
        // Keychain 里有会话就直接进主界面。这里只做「有没有」的判断，
        // 会话是否还有效由第一次真实请求的 401 来发现——启动时多打一次
        // 网络请求会让离线开 App 卡在转圈，而离线拍照恰恰是这个 App 的主场景。
        if SessionStore.current != nil, account == nil {
            account = AccountUser(id: 0, username: "", displayName: "", avatarUrl: "", role: "USER")
        }
        // 旧版的 Int 键作废（命名空间已换），顺手清掉
        UserDefaults.standard.removeObject(forKey: "selectedProjectId")
        if let data = UserDefaults.standard.data(forKey: "selectedRelayProject"),
           let saved = try? JSONDecoder().decode(RelayProject.self, from: data) {
            selectedProject = saved
            project = FieldProject(id: saved.id, name: saved.name,
                                   archivePath: "现场影像 / \(AppModel.today)")
            await UploadQueue.shared.configure(project: saved) { [weak self] in
                await self?.refresh()
            }
        }
        didRestore = true
        try? await EvidenceStore.shared.sweepOrphans()
        await refresh()
        // 上次没传完的，启动就接着传；停在中转区的顺手查一次回执
        if selectedProject != nil {
            await UploadQueue.shared.kick()
            cloudExpiry = await UploadQueue.shared.checkDelivered()
            await refresh()
        }
        // 上传自愈心跳（dev-board#241）：滞留的「传输中」与失败件不能等用户来点，
        // 现场拍完手机就揣兜里了——每分钟自动续传，失败按退避重试
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await UploadQueue.shared.autoKick()
            }
        }
    }

    func store(data: Data, kind: MediaKind, at: Date, location: (lat: Double, lon: Double, accuracy: Double)?) async {
        do {
            _ = try await EvidenceStore.shared.save(
                data: data, kind: kind, capturedAt: at,
                location: location, device: Device.facts
            )
            await refresh()
            kickUpload()
            await saveToAlbumIfEnabled()
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 存进系统相册（开关打开时）。**与上传彼此独立**——
    /// 相册存不进去不该影响上传，反之亦然，两条链任何一条断了另一条都要继续走。
    private func saveToAlbumIfEnabled() async {
        guard Prefs.saveToAlbum else { return }
        // 录音不进相册：PhotoKit 没有音频资产，混进来只会在这个循环里反复空转。
        let pending = items.filter { !$0.savedToAlbum && $0.kind != .audio }
        for item in pending {
            do {
                try await AlbumSaver.save(url: item.localURL, kind: item.kind)
                try? await EvidenceStore.shared.markSavedToAlbum(item.id)
            } catch {
                // 不打断、不弹窗。相册失败最常见的原因是没给权限，
                // 设置页里已经把这件事说清楚了，这里再弹一次是噪音。
                albumWarning = error.localizedDescription
            }
        }
        await refresh()
    }

    var albumWarning: String?
    var lastError: String?
}
