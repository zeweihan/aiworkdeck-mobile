// ActivityKit 的 Activity 没标 Sendable，但它本就是跨线程安全的句柄；
// 不加这条，每个 Task { await a.update } 都报「sending risks data races」。
@preconcurrency import ActivityKit
import Foundation

/// 录音 Live Activity 的生命周期（请求 / 更新 / 结束）。只在 App target 里，
/// 由 AudioRecorderService 在开录、中断、续录、停止四个时刻调用。
/// 这里任何失败都吞掉——常驻展示是锦上添花，不能反过来影响录音本身。
@MainActor
final class RecordingActivityController {
    private var activity: Activity<RecordingActivityAttributes>?

    init() {
        // 上次进程没走完（崩溃、被系统杀）留下的活动会一直挂在锁屏上，启动即收掉
        for stale in Activity<RecordingActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func start(projectName: String, state: RecordingActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        activity = try? Activity.request(
            attributes: RecordingActivityAttributes(projectName: projectName),
            content: .init(state: state, staleDate: nil))
    }

    func update(state: RecordingActivityAttributes.ContentState) {
        guard let a = activity else { return }
        Task { await a.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
