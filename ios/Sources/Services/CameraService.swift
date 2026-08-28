// AVFoundation 的类型全都不是 Sendable，而 session 配置本来就必须在专用串行队列上做。
// @preconcurrency 是这里的正解：不是掩盖问题，是声明「这个模块的并发标注还没跟上，
// 隔离由我们自己的 sessionQueue 保证」。
@preconcurrency import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

/// 相机。取证要求「确实来自相机」，所以全程自己控制 AVCaptureSession，
/// 不用 UIImagePickerController（那个可以选相册，来源说不清）。
///
/// 照片走 maxPhotoQualityPrioritization = .quality 直出 JPEG，不做二次压缩——
/// 压缩会改变字节，哈希就证明不了「原始采集」。
@MainActor
@Observable
final class CameraService: NSObject {
    enum Mode { case photo, video }

    private(set) var isRunning = false
    private(set) var isRecording = false
    private(set) var permissionDenied = false
    private(set) var recordingSeconds = 0
    var mode: Mode = .photo

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.aiworkdeck.mobile.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var micAdded = false
    private var timer: Timer?

    /// 一条采集完成后回调。UI 层拿去落库。
    var onCaptured: ((Data, MediaKind, Date) -> Void)?

    // MARK: - 生命周期

    func start() async {
        guard await ensureAuthorized(.video) else {
            permissionDenied = true
            return
        }
        // 去系统设置里把权限打开再回来：拒绝态要能自愈，不能一直停在提示页
        permissionDenied = false
        await configureIfNeeded()
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
        isRunning = true
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        isRunning = false
    }

    private var configured = false

    private func configureIfNeeded() async {
        guard !configured else { return }
        configured = true

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [session, photoOutput, movieOutput] in
                session.beginConfiguration()
                session.sessionPreset = .high

                if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: cam),
                   session.canAddInput(input) {
                    session.addInput(input)
                }
                if session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                    photoOutput.maxPhotoQualityPrioritization = .quality
                }
                if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

                session.commitConfiguration()
                cont.resume()
            }
        }
    }

    /// 麦克风按需申请：只拍照的用户不该被要求授权录音。
    private func addMicIfNeeded() async {
        guard !micAdded, await ensureAuthorized(.audio) else { return }
        micAdded = true
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [session] in
                session.beginConfiguration()
                if let mic = AVCaptureDevice.default(for: .audio),
                   let mi = try? AVCaptureDeviceInput(device: mic),
                   session.canAddInput(mi) {
                    session.addInput(mi)
                }
                session.commitConfiguration()
                cont.resume()
            }
        }
    }

    private func ensureAuthorized(_ media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: media)
        default: return false
        }
    }

    // MARK: - 采集

    func shoot() {
        guard !isRecording else { return }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.photoQualityPrioritization = .quality
        sessionQueue.async { [photoOutput, weak self] in
            guard let self else { return }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleRecording() async {
        if isRecording {
            movieOutput.stopRecording()
            return
        }
        await addMicIfNeeded()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mov")
        sessionQueue.async { [movieOutput, weak self] in
            guard let self else { return }
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
        isRecording = true
        recordingSeconds = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordingSeconds += 1 }
        }
    }
}

// MARK: - 代理

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let at = Date()
        Task { @MainActor [weak self] in
            self?.onCaptured?(data, .photo, at)
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let at = Date()
        let data = try? Data(contentsOf: outputFileURL, options: .mappedIfSafe)
        try? FileManager.default.removeItem(at: outputFileURL)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRecording = false
            self.timer?.invalidate()
            self.timer = nil
            self.recordingSeconds = 0
            if error == nil, let data { self.onCaptured?(data, .video, at) }
        }
    }
}

// MARK: - 取景预览

/// AVCaptureVideoPreviewLayer 的 SwiftUI 包装。用 layerClass 而不是手动加子 layer，
/// 这样 layer 会自动跟随 view 的 bounds，旋转和分屏都不用自己处理。
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - 位置

/// 一次性取位置：只在拍摄时读一次，不做后台定位。
/// 精度一并记下——没有精度的坐标在质证时说明不了问题。
@MainActor
@Observable
final class LocationStamper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var last: (lat: Double, lon: Double, accuracy: Double)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func begin() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func end() { manager.stopUpdatingLocation() }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        let v = (l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy)
        Task { @MainActor [weak self] in self?.last = v }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}

enum Device {
    static var facts: DeviceFacts {
        var sys = utsname()
        uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return DeviceFacts(
            model: model,
            osVersion: UIDevice.current.systemVersion,
            appVersion: "\(v) (\(b))"
        )
    }
}
