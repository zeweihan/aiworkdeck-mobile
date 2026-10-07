#if DEBUG
@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Observation

@MainActor
@Observable
final class DualCaptureService {
    private(set) var isRunning = false
    private(set) var isBusy = false
    private(set) var isCapturing = false
    private(set) var statusKey = "dual.prototype.idle"
    private(set) var error: String?
    private(set) var diagnostics = ""
    private(set) var outputURL: URL?
    private(set) var rearPreview: Data?
    private(set) var frontPreview: Data?
    private var engine: DualCaptureEngine?
    private var generation = UUID()
    private var stopTask: Task<Void, Never>?
    /// A newly presented prototype must also wait for the previous instance to release its cameras.
    private static var pendingStop: Task<Void, Never>?
    private static var pendingStopID: UUID?

    func start() async {
        guard !isBusy, !isRunning else { return }
        guard !captureConflict else { statusKey = "dual.prototype.audioBusy"; return }
        let generation = UUID()
        self.generation = generation
        isBusy = true
        error = nil
        if let pendingStop = Self.pendingStop { await pendingStop.value }
        guard self.generation == generation else { return }
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard self.generation == generation else { return }
        guard authorized else { isBusy = false; statusKey = "dual.prototype.permission"; return }
        guard !captureConflict else { isBusy = false; statusKey = "dual.prototype.audioBusy"; return }
        // This existing async method waits for the old camera queue to stop and release its mic.
        // The prototype never activates an audio session or restarts the old camera on exit.
        await CameraService.shared.prepareForAudioRecording()
        guard self.generation == generation else { return }
        guard !captureConflict else { isBusy = false; statusKey = "dual.prototype.audioBusy"; return }
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            isBusy = false; statusKey = "dual.prototype.unsupported"; return
        }
        let engine = DualCaptureEngine(generation: generation) { [weak self] event in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                switch event {
                case .running(let details):
                    self.isBusy = false; self.isRunning = true
                    self.statusKey = "dual.prototype.running"; self.diagnostics = details
                case .preview(let rear, let front):
                    self.rearPreview = rear; self.frontPreview = front
                case .saved(let url, let details):
                    self.isCapturing = false; self.outputURL = url
                    self.statusKey = "dual.prototype.saved"; self.diagnostics = details
                case .failed(let message, let stopped):
                    self.isBusy = false; self.isCapturing = false; self.error = message
                    self.statusKey = "dual.prototype.failed"
                    if stopped { self.isRunning = false }
                }
            }
        }
        self.engine = engine
        engine.start()
    }

    func capture(project: RelayProject?) {
        guard isRunning, !isCapturing, !isBusy else { return }
        guard !captureConflict else { stop(); statusKey = "dual.prototype.audioBusy"; return }
        isCapturing = true; error = nil; outputURL = nil
        statusKey = "dual.prototype.capturing"
        engine?.capture(project: project, requestedAt: CMClockGetTime(CMClockGetHostTimeClock()).seconds,
                        wallClock: Date())
    }

    @discardableResult
    func stop() -> Task<Void, Never> {
        if let stopTask { return stopTask }
        let generation = UUID() // Pending permission and queued UI callbacks can no longer restart this view.
        self.generation = generation
        let stoppingEngine = engine
        engine = nil
        isRunning = false; isBusy = true; isCapturing = false
        rearPreview = nil; frontPreview = nil
        statusKey = "dual.prototype.stopped"
        let previousStop = Self.pendingStop
        let stopID = UUID()
        Self.pendingStopID = stopID
        let task = Task { @MainActor [weak self] in
            if let previousStop { await previousStop.value }
            if let stoppingEngine { await stoppingEngine.stop() }
            if Self.pendingStopID == stopID {
                Self.pendingStop = nil
                Self.pendingStopID = nil
            }
            guard let self, self.generation == generation else { return }
            self.isBusy = false
            self.stopTask = nil
        }
        Self.pendingStop = task
        stopTask = task
        return task
    }

    var captureConflict: Bool {
        AudioRecorderService.shared.isRecording || AudioRecorderService.shared.isBusy ||
            CameraService.shared.isRecording
    }
}

/// AVFoundation objects and the gate are confined to `queue`. Only Data/URL/string events escape.
private final class DualCaptureEngine: NSObject, AVCaptureDataOutputSynchronizerDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case running(String), preview(Data, Data), saved(URL, String), failed(String, stopped: Bool)
    }

    private let queue = DispatchQueue(label: "com.aiworkdeck.debug.dual-capture")
    private let session = AVCaptureMultiCamSession()
    private let rearOutput = AVCaptureVideoDataOutput()
    private let frontOutput = AVCaptureVideoDataOutput()
    private let context = CIContext()
    private let generation: UUID
    private let event: @Sendable (Event) -> Void
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private var sources: [DualFrameSnapshot.Source] = []
    private var gate = DualFramePairGate()
    private var project: RelayProject?
    private var wallClock = Date()
    private var lastPreviewTime = 0.0
    private var observers: [NSObjectProtocol] = []
    private var running = false

    init(generation: UUID, event: @escaping @Sendable (Event) -> Void) {
        self.generation = generation
        self.event = event
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) {
                [weak self] note in
                let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int).map(String.init) ?? "runtime"
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.stopOnQueue()
                    self.event(.failed("Session interrupted (\(reason)); start again explicitly.", stopped: true))
                }
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start() {
        queue.async { [self] in
            do {
                try configure()
                guard session.hardwareCost <= 1, session.systemPressureCost <= 1 else { throw PrototypeError.resourceCost }
                session.startRunning()
                guard session.isRunning else { throw PrototypeError.cannotStart }
                running = true
                event(.running("front/back; 30 fps; rotation=90°; mirrored=false; " +
                    "hardwareCost=\(session.hardwareCost); pressureCost=\(session.systemPressureCost)"))
            } catch {
                stopOnQueue()
                event(.failed(String(describing: error), stopped: true))
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopOnQueue()
                continuation.resume()
            }
        }
    }

    private func stopOnQueue() {
        running = false
        gate.cancel()
        synchronizer?.setDelegate(nil, queue: nil)
        if session.isRunning { session.stopRunning() }
    }

    func capture(project: RelayProject?, requestedAt: Double, wallClock: Date) {
        queue.async { [self] in
            guard running, gate.request == nil else {
                event(.failed("Session is not ready for a shutter request.", stopped: !running)); return
            }
            let request = DualFramePairGate.Request(id: UUID(), generation: generation, hostSeconds: requestedAt)
            self.project = project
            self.wallClock = wallClock
            gate.arm(request)
            queue.asyncAfter(deadline: .now() + DualFramePairGate.timeoutSeconds) { [weak self] in
                guard let self, self.gate.request?.id == request.id else { return }
                self.gate.cancel()
                self.event(.failed("No valid fresh frame pair within 3 seconds.", stopped: false))
            }
        }
    }

    private func configure() throws {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video, position: .unspecified)
        guard let rear = discovery.devices.first(where: { $0.position == .back }),
              let front = discovery.devices.first(where: { $0.position == .front }),
              discovery.supportedMultiCamDeviceSets.contains(where: { $0.contains(rear) && $0.contains(front) }) else {
            throw PrototypeError.unsupportedPair
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // MultiCam uses inputPriority. Never copy the single-camera .high preset here.
        session.automaticallyConfiguresApplicationAudioSession = false
        sources = try zip([rear, front], [rearOutput, frontOutput]).map { device, output in
            let formats = device.formats.filter { format in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return format.isMultiCamSupported && size.width <= 1920 && size.height <= 1080 &&
                    size.width >= 640 && format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
            }.sorted {
                let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                return a.width * a.height < b.width * b.height
            }
            guard let format = formats.first else { throw PrototypeError.unsupportedFormat }
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(output) else { throw PrototypeError.configuration }
            session.addInputWithNoConnections(input)
            session.addOutputWithNoConnections(output)
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            guard let port = input.ports.first(where: { $0.mediaType == .video }) else { throw PrototypeError.configuration }
            let connection = AVCaptureConnection(inputPorts: [port], output: output)
            guard session.canAddConnection(connection), connection.isVideoRotationAngleSupported(90) else {
                throw PrototypeError.configuration
            }
            session.addConnection(connection)
            connection.videoRotationAngle = 90
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return DualFrameSnapshot.Source(cameraID: device.uniqueID, cameraType: device.deviceType.rawValue,
                position: device.position == .front ? "front" : "back", width: size.height, height: size.width,
                rotationDegrees: 90, mirrored: false)
        }
        let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [rearOutput, frontOutput])
        synchronizer.setDelegate(self, queue: queue)
        self.synchronizer = synchronizer
    }

    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard running, synchronizer === self.synchronizer else { return }
        let rear = synchronizedDataCollection.synchronizedData(for: rearOutput) as? AVCaptureSynchronizedSampleBufferData
        let front = synchronizedDataCollection.synchronizedData(for: frontOutput) as? AVCaptureSynchronizedSampleBufferData
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        if let request = gate.request {
            let decision = gate.evaluate(requestID: request.id, generation: generation,
                rear: stamp(rear), front: stamp(front), now: now)
            if case .accepted(let pair) = decision {
                guard let rear, let front, let rearBuffer = CMSampleBufferGetImageBuffer(rear.sampleBuffer),
                      let frontBuffer = CMSampleBufferGetImageBuffer(front.sampleBuffer) else {
                    event(.failed("Frame buffers are missing.", stopped: false)); return
                }
                do {
                    // Encoding is synchronous on the delegate queue: no borrowed buffers escape.
                    let url = try DualFrameSnapshot.save(rear: rearBuffer, front: frontBuffer, pair: pair,
                        project: project, rearSource: sources[0], frontSource: sources[1],
                        wallClock: wallClock, context: context)
                    event(.saved(url, "skew=\(pair.skewSeconds)s; max=\(pair.maximumSkewSeconds)s; " +
                        "rearPTS=\(pair.rear.ptsValue)/\(pair.rear.ptsTimescale); " +
                        "frontPTS=\(pair.front.ptsValue)/\(pair.front.ptsTimescale)"))
                } catch { event(.failed(String(describing: error), stopped: false)) }
            } else if decision == .rejected(.timedOut) {
                event(.failed("No valid fresh frame pair within 3 seconds.", stopped: false))
            }
        }
        guard now - lastPreviewTime >= 0.33, let rear, let front,
              !rear.sampleBufferWasDropped, !front.sampleBufferWasDropped,
              let rearBuffer = CMSampleBufferGetImageBuffer(rear.sampleBuffer),
              let frontBuffer = CMSampleBufferGetImageBuffer(front.sampleBuffer) else { return }
        lastPreviewTime = now
        if let rearData = try? DualFrameSnapshot.jpeg(rearBuffer, context: context, preview: true),
           let frontData = try? DualFrameSnapshot.jpeg(frontBuffer, context: context, preview: true) {
            event(.preview(rearData, frontData))
        }
    }

    private func stamp(_ data: AVCaptureSynchronizedSampleBufferData?) -> DualFrameStamp? {
        guard let data else { return nil }
        let pts = CMSampleBufferGetPresentationTimeStamp(data.sampleBuffer)
        var hostSeconds: Double?
        if pts.isNumeric, let clock = session.synchronizationClock {
            let converted = CMSyncConvertTime(pts, from: clock, to: CMClockGetHostTimeClock())
            if converted.isNumeric { hostSeconds = converted.seconds }
        }
        return DualFrameStamp(ptsValue: pts.value, ptsTimescale: pts.timescale, ptsEpoch: pts.epoch,
            hostSeconds: hostSeconds, dropped: data.sampleBufferWasDropped)
    }

    private enum PrototypeError: Error {
        case unsupportedPair, unsupportedFormat, configuration, resourceCost, cannotStart
    }
}
#endif
