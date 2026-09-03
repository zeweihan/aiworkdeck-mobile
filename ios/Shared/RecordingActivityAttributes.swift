import ActivityKit
import Foundation

/// 录音 Live Activity 的静态属性与动态状态。同时编进 App 与扩展——两边必须是
/// 同一份源码，字段对不上 ActivityKit 解不出 ContentState，卡片直接空白。
struct RecordingActivityAttributes: ActivityAttributes {
    /// 与 RecordingClock 同构：扩展里的计时以 resumedAt - elapsedBase 为起点自走，
    /// 中断（paused）时显示 elapsedBase 的静态值。不靠推送刷新。
    struct ContentState: Codable, Hashable {
        var elapsedBase: TimeInterval
        var resumedAt: Date?
        var paused: Bool
    }

    var projectName: String
}
