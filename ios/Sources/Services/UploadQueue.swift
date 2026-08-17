import Foundation

/// 上传队列。
///
/// **串行，一次一条。** 现场是弱网，并发上传会让每一条都变慢、且失败面变大；
/// 一条一条走，失败只影响一条，进度也说得清。
///
/// 状态推进全部经过 EvidenceStore 落盘——进程被杀、App 被切走再回来，
/// 队列能从磁盘恢复，不依赖内存里的任何东西。
actor UploadQueue {
    static let shared = UploadQueue()

    private var running = false
    private var projectId: Int?

    /// 进度回调，UI 层订阅。
    private var onChange: (@Sendable () async -> Void)?

    func configure(projectId: Int?, onChange: (@Sendable () async -> Void)?) {
        self.projectId = projectId
        self.onChange = onChange
    }

    /// 启动一轮。已经在跑就直接返回，不排队叠加。
    func kick() async {
        guard !running, let projectId else { return }
        running = true
        defer { running = false }

        while true {
            let pending = (try? await EvidenceStore.shared.loadAll())?
                .filter { $0.state == .waiting } ?? []
            guard let item = pending.last else { break }   // 先传最早拍的

            do {
                try await EvidenceStore.shared.updateState(item.id, to: .moving, progress: 0)
                await onChange?()

                try await API.shared.upload(
                    item: item,
                    projectId: projectId,
                    fileName: Self.fileName(for: item)
                ) { _ in }

                try await EvidenceStore.shared.updateState(item.id, to: .arrived, progress: 1)
                await onChange?()
            } catch {
                // 失败退回 failed 而不是 waiting：否则会立刻被下一轮捞起来无限重试，
                // 把弱网下本来能成的那几条也挤掉。重试由用户或下次启动触发。
                try? await EvidenceStore.shared.updateState(item.id, to: .failed, progress: 0)
                await onChange?()
                break
            }
        }
    }

    /// 把失败的重新排回待传。用户手动点「重试」时调用。
    func retryFailed() async {
        let failed = (try? await EvidenceStore.shared.loadAll())?
            .filter { $0.state == .failed } ?? []
        for f in failed {
            try? await EvidenceStore.shared.updateState(f.id, to: .waiting, progress: 0)
        }
        await onChange?()
        await kick()
    }

    /// 文件名带上采集时刻，桌面端按名字排序即是时间序。
    /// 不用原始 UUID 当名字——律师在文件夹里看到一串十六进制没有任何意义。
    private static func fileName(for item: CaptureItem) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: item.capturedAt)
        let ext = item.kind == .photo ? "jpg" : "mov"
        let short = item.id.uuidString.prefix(4)
        return "现场影像-\(stamp)-\(short).\(ext)"
    }
}
