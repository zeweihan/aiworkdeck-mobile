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

    static var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
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
