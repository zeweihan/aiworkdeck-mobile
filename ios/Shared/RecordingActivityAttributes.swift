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
    /// 开始录音那一刻的界面语言（dev-board#837：海外版是英文）。扩展是另一个进程，
    /// 读不到 App 的语言状态，只能随属性带过去。可选：旧版本起的活动解出来是 nil，按中文显示。
    var locale: String? = nil
}
