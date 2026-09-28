@preconcurrency import AVFoundation
import Foundation
import UIKit

private let audioSessionQueue = DispatchQueue(label: "com.aiworkdeck.mobile.audiosession")

/// All session changes use one queue so stopping cannot deactivate a newer recording.
func configureAudioSession(active: Bool, playback: Bool = false) async -> Bool {
    await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
        audioSessionQueue.async {
            do {
                let session = AVAudioSession.sharedInstance()
                if active {
                    try session.setCategory(playback ? .playback : .record, mode: .default)
                }
                try session.setActive(active)
                cont.resume(returning: true)
            } catch {
                cont.resume(returning: false)
            }
        }
    }
}

@MainActor
@Observable
final class AudioRecorderService: NSObject {
    static let shared = AudioRecorderService()
    private(set) var isRecording = false
    private(set) var isInterrupted = false
    private(set) var isBusy = false
    private(set) var permissionDenied = false
    private(set) var recordingSeconds = 0
    private(set) var lastError: String?
    private(set) var lastSavedID: UUID?

    private var recorder: AVAudioRecorder?
    private var draft: RecordingDraft?
    private var clock = RecordingClock()
    private var timer: Timer?
    private let activity = RecordingActivityController()
    private var recovering = false
    var onStored: (() async -> Void)?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                if type == .began { self.synchronize() }
                else { await self.resumeIfInterrupted() }
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.stop() }
        }
    }

    func toggle(project: RelayProject?, location: (lat: Double, lon: Double, accuracy: Double)?) async {
        guard !isBusy else { return }
        if isRecording { await stop() }
        else { await start(project: project, location: location) }
    }

    /// stop() closes the file synchronously; saving must not depend on a delegate arriving
    /// after an interruption. Both delegate and intent use this idempotent path.
    func stop() async {
        guard !isBusy, let r = recorder, let draft else { return }
        isBusy = true
        let task = UIApplication.shared.beginBackgroundTask(withName: "Save recording")
        defer {
            isBusy = false
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
        r.delegate = nil
        r.stop()
        recorder = nil
        self.draft = nil
        timer?.invalidate()
        timer = nil
        activity.end()
        _ = await configureAudioSession(active: false)
        isRecording = false
        isInterrupted = false
        recordingSeconds = 0
        await save(draft)
    }

    private func save(_ draft: RecordingDraft) async {
        do {
            let duration = try await AVURLAsset(url: draft.audioURL).load(.duration)
            guard duration.seconds.isFinite, duration.seconds > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let item = try await EvidenceStore.shared.saveRecording(draft)
            draft.remove() // Only remove the source after the manifest has committed.
            lastSavedID = item.id
            lastError = nil
            await onStored?()
        } catch {
            // Metadata and audio survive for the next foreground/launch retry.
            lastError = tr("rec.saveFailed")
        }
    }

    func recoverPending() async {
        guard !recovering, !isBusy else { return }
        recovering = true
        defer { recovering = false }
        do {
            for pending in try RecordingDraft.pending() where pending.id != draft?.id {
                await save(pending)
            }
        } catch { lastError = tr("rec.saveFailed") }
    }

    private func start(project: RelayProject?, location: (lat: Double, lon: Double, accuracy: Double)?) async {
        guard !isBusy, recorder == nil else { return }
        isBusy = true
        defer { isBusy = false }
        guard await ensureAuthorized() else { permissionDenied = true; return }
        permissionDenied = false
        lastError = nil
        lastSavedID = nil
        await CameraService.shared.prepareForAudioRecording()
        guard await configureAudioSession(active: true) else {
            lastError = tr("rec.startFailed")
            return
        }
        let draft = RecordingDraft(id: UUID(), startedAt: Date(), project: project,
                                   latitude: location?.lat, longitude: location?.lon,
                                   accuracy: location?.accuracy, device: Device.facts)
        do {
            try draft.persist()
            let r = try AVAudioRecorder(url: draft.audioURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
            ])
            r.delegate = self
            guard r.prepareToRecord() else { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: draft.audioURL.path)
            guard r.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = r
            self.draft = draft
            clock.start(at: Date())
            isRecording = true
            isInterrupted = false
            recordingSeconds = 0
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.synchronize() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            activity.start(projectName: project?.name ?? "", state: activityState)
        } catch {
            draft.remove() // Recording never started.
            _ = await configureAudioSession(active: false)
            lastError = tr("rec.startFailed")
        }
    }

    /// Use recorded duration, not wall time: a suspended timer is not evidence of audio.
    private func synchronize() {
        guard let r = recorder, isRecording else { return }
        let changed = isInterrupted != !r.isRecording
        clock.synchronize(seconds: max(clock.elapsedBase, r.currentTime), running: r.isRecording, at: Date())
        recordingSeconds = Int(clock.elapsed(at: Date()))
        isInterrupted = !r.isRecording
        if changed { activity.update(state: activityState) }
    }

    func resumeIfInterrupted() async {
        guard !isBusy, let r = recorder else { return }
        synchronize()
        guard !r.isRecording else {
            activity.update(state: activityState)
            return
        }
        // Keep stop available while session activation awaits another process.
        let activated = await configureAudioSession(active: true)
        guard recorder === r, !isBusy else { return }
        if activated { _ = r.record() }
        synchronize()
        activity.update(state: activityState)
    }

    private var activityState: RecordingActivityAttributes.ContentState {
        .init(elapsedBase: clock.elapsedBase, resumedAt: clock.resumedAt, paused: clock.paused)
    }

    private func ensureAuthorized() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .undetermined: await AVAudioApplication.requestRecordPermission()
        default: false
        }
    }

#if DEBUG
    func beginFakeRecording(seconds: Int) {
        guard Shot.isOn else { return }
        isRecording = true
        recordingSeconds = seconds
    }
#endif
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.recorder?.url == url else { return }
            await self.stop()
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.recorder?.url == url else { return }
            await self.stop()
        }
    }
}
