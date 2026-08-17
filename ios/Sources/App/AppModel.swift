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

    func didLogin(_ result: LoginResult) async {
        account = result.user
        // 新账号还没有项目，展示名先顶着；等接了项目列表再换成真实项目
        if result.isNewUser {
            project = FieldProject(id: "unbound", name: "未选择项目",
                                   archivePath: "现场影像 / \(AppModel.today)")
        }
        await refresh()
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
        didRestore = true
        try? await EvidenceStore.shared.sweepOrphans()
        await refresh()
    }

    func store(data: Data, kind: MediaKind, at: Date, location: (lat: Double, lon: Double, accuracy: Double)?) async {
        do {
            _ = try await EvidenceStore.shared.save(
                data: data, kind: kind, capturedAt: at,
                location: location, device: Device.facts
            )
            await refresh()
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
    }

    var lastError: String?
}
