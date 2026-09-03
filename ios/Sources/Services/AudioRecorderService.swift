// AVFoundation 的并发标注没跟上（同 CameraService），隔离由 MainActor 保证。
@preconcurrency import AVFoundation
import Foundation

/// 现场录音。用 AVAudioRecorder 而不是复用 AVCaptureSession——
/// 录音不需要摄像头，不该点亮相机、占着取景会话。
///
/// 参数：AAC（m4a）、44.1kHz、单声道、64kbps。人声清晰，一小时约 28MB，
/// 走与照片/录像同一条 EvidenceStore → UploadQueue 链路，不另起存储。
///
/// 进程级单例：锁屏卡片 / 灵动岛的停止意图在主进程执行，要能找到正在录的这一个。
/// 退后台、锁屏靠 Info.plist 的 UIBackgroundModes audio 续录；来电等系统中断由
/// AVAudioSession.interruptionNotification 驱动时钟暂停/续录，写的仍是同一个文件。
@MainActor
@Observable
final class AudioRecorderService: NSObject {
    static let shared = AudioRecorderService()

    private(set) var isRecording = false
    /// 系统中断中（来电、Siri、闹钟）：AVAudioRecorder 已被系统暂停，结束后自动续录
    private(set) var isInterrupted = false
    private(set) var permissionDenied = false
    private(set) var recordingSeconds = 0

    private var recorder: AVAudioRecorder?
    private var startedAt = Date()
    private var clock = RecordingClock()
    private var timer: Timer?
    private let activity = RecordingActivityController()

    /// 一段录音完成后回调，UI 层拿去落库。时间用开始录音的时刻——
    /// 取证语义上「什么时候开始录」比「什么时候按停」重要。
    var onCaptured: ((Data, Date) -> Void)?

    private override init() {
        super.init()
        // 单例活到进程结束，不用留 token 反注册
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in self?.handleInterruption(type) }
        }
    }

    /// projectName 只用于灵动岛 / 锁屏卡片上的展示
    func toggle(projectName: String) async {
        if isRecording { stop() } else { await start(projectName: projectName) }
    }

    /// 收尾在 delegate 回调里做：stop() 之后文件才算写完。
    func stop() {
        recorder?.stop()
    }

    private func start(projectName: String) async {
        guard await ensureAuthorized() else {
            permissionDenied = true
            return
        }
        permissionDenied = false

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aud-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return }
        r.delegate = self
        guard r.record() else { return }

        recorder = r
        startedAt = Date()
        clock.start(at: startedAt)
        isRecording = true
        isInterrupted = false
        recordingSeconds = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        activity.start(projectName: projectName, state: activityState)
    }

    private func tick() {
        recordingSeconds = Int(clock.elapsed(at: Date()))
    }

    private var activityState: RecordingActivityAttributes.ContentState {
        .init(elapsedBase: clock.elapsedBase, resumedAt: clock.resumedAt, paused: clock.paused)
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType) {
        guard isRecording, let r = recorder else { return }
        switch type {
        case .began:
            // 系统已经把 recorder 暂停了，这里只对齐时钟与界面
            clock.interrupt(at: Date())
            isInterrupted = true
            tick()
            activity.update(state: activityState)
        case .ended:
            // 不看 shouldResume：取证录音能续就续。record() 在同一文件上接着写；
            // 续不上（会话被别人占死）就收尾落库，已录的内容不能丢。
            try? AVAudioSession.sharedInstance().setActive(true)
            if r.record() {
                clock.resume(at: Date())
                isInterrupted = false
                activity.update(state: activityState)
            } else {
                stop()
            }
        @unknown default:
            break
        }
    }

    private func ensureAuthorized() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        default: return false
        }
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ r: AVAudioRecorder, successfully flag: Bool) {
        let url = r.url
        let data: Data? = flag ? (try? Data(contentsOf: url, options: .mappedIfSafe)) : nil
        try? FileManager.default.removeItem(at: url)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRecording = false
            self.isInterrupted = false
            self.timer?.invalidate()
            self.timer = nil
            self.recorder = nil
            self.recordingSeconds = 0
            self.activity.end()
            try? AVAudioSession.sharedInstance().setActive(false)
            if let data { self.onCaptured?(data, self.startedAt) }
        }
    }
}
