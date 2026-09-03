import Foundation

/// 录音时钟。纯值类型，不碰 AVFoundation：录音舞台的计时器与 Live Activity 的
/// 内容状态都从这里派生，两处显示不会各算各的。
///
/// 系统中断（来电、Siri、闹钟）时 AVAudioRecorder 被暂停，当前运行段的秒数并入
/// `elapsedBase`；续录时另起一段。`elapsed(at:)` = 已累计 + 当前段。
struct RecordingClock: Equatable {
    /// 当前运行段之前累计的秒数
    private(set) var elapsedBase: TimeInterval = 0
    /// 当前运行段的起点；nil = 未开始或中断中
    private(set) var resumedAt: Date?
    private(set) var paused = false

    mutating func start(at now: Date) {
        elapsedBase = 0
        resumedAt = now
        paused = false
    }

    /// 重复调用幂等：系统可能连发两次 .began，第二次不能再扣一段
    mutating func interrupt(at now: Date) {
        guard let from = resumedAt else { return }
        elapsedBase += max(0, now.timeIntervalSince(from))
        resumedAt = nil
        paused = true
    }

    mutating func resume(at now: Date) {
        guard paused else { return }
        resumedAt = now
        paused = false
    }

    func elapsed(at now: Date) -> TimeInterval {
        elapsedBase + (resumedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}
