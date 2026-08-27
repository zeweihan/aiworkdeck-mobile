// AVFoundation 的并发标注没跟上（同 CameraService），隔离由 MainActor 保证。
@preconcurrency import AVFoundation
import Foundation

/// 现场录音。用 AVAudioRecorder 而不是复用 AVCaptureSession——
/// 录音不需要摄像头，不该点亮相机、占着取景会话。
///
/// 参数：AAC（m4a）、44.1kHz、单声道、64kbps。人声清晰，一小时约 28MB，
/// 走与照片/录像同一条 EvidenceStore → UploadQueue 链路，不另起存储。
@MainActor
@Observable
final class AudioRecorderService: NSObject {
    private(set) var isRecording = false
    private(set) var permissionDenied = false
    private(set) var recordingSeconds = 0

    private var recorder: AVAudioRecorder?
    private var startedAt = Date()
    private var timer: Timer?

    /// 一段录音完成后回调，UI 层拿去落库。时间用开始录音的时刻——
    /// 取证语义上「什么时候开始录」比「什么时候按停」重要。
    var onCaptured: ((Data, Date) -> Void)?

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    /// 收尾在 delegate 回调里做：stop() 之后文件才算写完。
    func stop() {
        recorder?.stop()
    }

    private func start() async {
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
        isRecording = true
        recordingSeconds = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordingSeconds += 1 }
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
            self.timer?.invalidate()
            self.timer = nil
            self.recorder = nil
            self.recordingSeconds = 0
            try? AVAudioSession.sharedInstance().setActive(false)
            if let data { self.onCaptured?(data, self.startedAt) }
        }
    }
}
