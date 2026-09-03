import AppIntents

/// 锁屏卡片 / 灵动岛上的「停止录音」。LiveActivityIntent 在**主进程**执行，
/// 通过 handler 钩子落到 AudioRecorderService.shared.stop()（WorkdeckApp 启动时装上）；
/// 扩展 target 里没人设 handler，perform 直接返回——按钮从不在扩展进程里做事。
struct StopRecordingIntent: LiveActivityIntent {
    // 只会在快捷指令 / 聚焦搜索露面的名字；isDiscoverable = false 后那里也不露面，
    // 用户看到的按钮文案在 RecordingLiveActivity 里走词典键。
    static let title: LocalizedStringResource = "Stop Recording"
    static let isDiscoverable = false

    @MainActor static var handler: (@MainActor () async -> Void)?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await Self.handler?()
        return .result()
    }
}
