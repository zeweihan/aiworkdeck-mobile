import AVFoundation
import os

/// 相机相关的运行日志。取证 App 的采集失败必须留痕：现场不可复现，
/// 事后只能靠日志回答「那一下到底为什么没拍上」。
let cameraLog = Logger(subsystem: "com.aiworkdeck.mobile", category: "camera")

/// 捕获会话在恢复 / 让渡麦克风时要做的动作。抽成协议只为一件事：
/// 真机上的黑屏在 CI 里复现不了（模拟器没有摄像头、也不会有系统中断），
/// 能钉住的只有「什么信号 → 做哪几步」这层判定。
/// 护栏 ios/Tests/CameraRecoveryTests.swift。
@MainActor
protocol CameraSessionControl: AnyObject {
    func stopRunning()
    /// 会话已被系统重置，拆掉全部输入输出重新配置
    func reconfigure()
    func startRunning()
    /// 录像收声：把麦克风输入加进捕获会话
    func addMicrophone()
    /// 把麦克风输入从捕获会话里摘掉，还给系统
    func removeMicrophone()
}

/// 相机会话的存活策略：用户意图 + 系统信号 → 动作序列（dev-board#461）。
///
/// 两件事合在这里，因为它们是同一个故障的两半：
/// 1. **麦克风归属**——录像收声把麦克风输入加进捕获会话，旧实现的 `micAdded`
///    是单向闩，加进去就再也不摘。此后每次现场录音（AVAudioRecorder + `.record`
///    会话）都是两个客户端抢同一个麦克风，捕获会话被系统中断。
/// 2. **中断 / 重置恢复**——旧实现一个观察者都没有：会话一旦被中断或遇上
///    `mediaServicesWereReset` 就永远起不来，取景是黑的、快门无声地失败，
///    只有重开 App 才好（这正是卡片里「重开 App 恢复」的由来）。
@MainActor
final class CameraRecovery {
    /// 用户此刻想不想要取景，**不是**会话的实际状态。恢复一律按意图点亮相机：
    /// 锁屏后台录音（Info.plist 的 UIBackgroundModes audio）期间它是 false，
    /// 中断结束绝不能顺手把摄像头打开。
    var desiredRunning = false

    /// 捕获会话是否正持有麦克风输入。一去一回都要经过这里。
    private(set) var micHeld = false

    private weak var control: CameraSessionControl?

    init(control: CameraSessionControl) { self.control = control }

    // MARK: - 系统信号

    func handleInterruptionEnded() {
        guard desiredRunning else { return }
        control?.startRunning()
    }

    /// 媒体服务被重启，会话里的输入输出全成了空壳，只能拆干净重建。
    /// 别的运行时错误不重建——重建本身是一次昂贵的 XPC，不是万能锤。
    func handleRuntimeError(_ code: AVError.Code) {
        guard code == .mediaServicesWereReset else { return }
        control?.stopRunning()
        // 重建出来的会话里没有麦克风：归属跟着归零，下次进录像档再加回去。
        // 忘了归零的表现是录出没有声音的视频。
        micHeld = false
        control?.reconfigure()
        guard desiredRunning else { return }
        control?.startRunning()
    }

    // MARK: - 麦克风归属

    func acquireMicrophone() {
        guard !micHeld else { return }
        micHeld = true
        control?.addMicrophone()
    }

    func releaseMicrophone() {
        guard micHeld else { return }
        micHeld = false
        control?.removeMicrophone()
    }
}
