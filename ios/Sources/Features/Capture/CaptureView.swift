import SwiftUI

/// 取景页。深色是功能性的：现场光线差、取景本来就是黑的、玻璃需要深底才成立。
/// 控制条压在真实取景画面上——这是全局第二处毛玻璃真正有意义的地方。
struct CaptureView: View {
    /// 三档采集模式。photo/video 由相机会话承担，audio 走 AudioRecorderService——
    /// 不塞进 CameraService.Mode 里，录音本来就不该经过相机。
    private enum CapMode: Hashable { case photo, video, audio }

    @Environment(AppModel.self) private var model
    @State private var camera = CameraService()
    @State private var recorder = AudioRecorderService()
    @State private var stamper = LocationStamper()
    @State private var flashId = UUID()
    @State private var showFlash = false
    @State private var mode: CapMode = .photo

    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if mode == .audio {
                audioStage
            } else if camera.permissionDenied {
                denied
            } else {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            }

            // 快门白闪：唯一的「拍到了」即时反馈，比任何提示都快
            if showFlash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            VStack {
                topBar
                Spacer()
                controls
            }
        }
        .statusBarHidden(true)
        .task {
            camera.onCaptured = { data, kind, at in
                let loc = stamper.last
                Task { await model.store(data: data, kind: kind, at: at, location: loc) }
            }
            recorder.onCaptured = { data, at in
                let loc = stamper.last
                Task { await model.store(data: data, kind: .audio, at: at, location: loc) }
            }
            stamper.begin()
            await camera.start()
        }
        .onChange(of: mode) { _, m in
            switch m {
            case .photo:
                camera.mode = .photo
                Task { await camera.start() }
            case .video:
                camera.mode = .video
                Task { await camera.start() }
            case .audio:
                // 录音不需要取景，停掉相机会话省电；切回来再启
                camera.stop()
            }
        }
        .onDisappear {
            // 录到一半退出：停表并落库，不丢已录的内容——现场不可复现
            if recorder.isRecording { recorder.stop() }
            camera.stop()
            stamper.end()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: T.Sp.s3) {
            Button(action: { camera.stop(); onClose() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: T.touchMin, height: T.touchMin)
            }
            .accessibilityLabel("关闭拍摄")

            VStack(alignment: .leading, spacing: 1) {
                Text(model.project.name)
                    .font(T.F.small())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("归档至 \(model.project.archivePath)")
                    .font(T.F.nano())
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 0)

            // 位置精度：没有精度的坐标在质证时说明不了问题，所以直接显示出来
            HStack(spacing: 4) {
                Circle()
                    .fill(stamper.last == nil ? Color.white.opacity(0.3) : T.S.arrivedOnDark)
                    .frame(width: 5, height: 5)
                Text(locationCaption)
                    .font(T.F.mono(10))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, T.Sp.s3)
        .padding(.vertical, T.Sp.s2)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var locationCaption: String {
        guard let l = stamper.last else { return "定位中" }
        return "±\(Int(l.accuracy.rounded()))m"
    }

    // MARK: - 底部控制

    private var controls: some View {
        VStack(spacing: T.Sp.s4) {
            if camera.isRecording {
                HStack(spacing: T.Sp.s1) {
                    Circle().fill(T.S.failed).frame(width: 7, height: 7)
                    Text(timeString(camera.recordingSeconds))
                        .font(T.F.mono(13, .medium))
                        .foregroundStyle(.white)
                }
            } else if !recorder.isRecording {
                // 录音进行中不给切换：计时在舞台中央，这里留白
                Picker("", selection: $mode) {
                    Text("照片").tag(CapMode.photo)
                    Text("录像").tag(CapMode.video)
                    Text("录音").tag(CapMode.audio)
                }
                .pickerStyle(.segmented)
                .frame(width: 252)
                .environment(\.colorScheme, .dark)
            }

            HStack {
                counter.frame(maxWidth: .infinity, alignment: .leading)
                shutter
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, T.Sp.gutter)
        .padding(.top, T.Sp.s4)
        .padding(.bottom, T.Sp.s6)
        .background {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .background(.ultraThinMaterial.opacity(0.5))
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var counter: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(model.tally.waiting + model.tally.moving + model.tally.arrived)")
                .font(T.F.mono(17, .medium))
                .foregroundStyle(.white)
            Text("本项目")
                .font(T.F.nano())
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var shutter: some View {
        Button {
            switch mode {
            case .photo:
                camera.shoot()
                flash()
            case .video:
                Task { await camera.toggleRecording() }
            case .audio:
                Task { await recorder.toggle() }
            }
        } label: {
            ZStack {
                Circle().stroke(.white.opacity(0.9), lineWidth: 2).frame(width: 74, height: 74)
                if camera.isRecording || recorder.isRecording {
                    RoundedRectangle(cornerRadius: 5).fill(T.S.failed).frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(mode == .photo ? Color.white : T.S.failed)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shutterLabel)
    }

    private var shutterLabel: String {
        if camera.isRecording { return "停止录像" }
        if recorder.isRecording { return "停止录音" }
        switch mode {
        case .photo: return "拍照"
        case .video: return "开始录像"
        case .audio: return "开始录音"
        }
    }

    private func flash() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.linear(duration: 0.06)) { showFlash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.easeOut(duration: 0.18)) { showFlash = false }
        }
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - 录音舞台

    /// 录音模式没有取景画面：深色底，等宽计时器就是全部的界面。
    private var audioStage: some View {
        Group {
            if recorder.permissionDenied {
                micDenied
            } else {
                VStack(spacing: T.Sp.s3) {
                    Text(timeString(recorder.recordingSeconds))
                        .font(T.F.hero())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    HStack(spacing: T.Sp.s2) {
                        if recorder.isRecording {
                            Circle().fill(T.S.failed).frame(width: 7, height: 7)
                        }
                        Eyebrow(text: recorder.isRecording ? "正在录音" : "按下开始录音",
                                color: .white.opacity(0.55))
                    }
                }
            }
        }
    }

    private var micDenied: some View {
        VStack(spacing: T.Sp.s3) {
            Text("没有麦克风权限")
                .font(T.F.heading())
                .foregroundStyle(.white)
            Text("去「设置 → Workdeck → 麦克风」打开后再回来。")
                .font(T.F.small())
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("打开设置") {
                if let u = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(u)
                }
            }
            .font(T.F.small())
            .foregroundStyle(T.S.movingOnDark)
            .padding(.top, T.Sp.s2)
        }
        .padding(T.Sp.s8)
    }

    private var denied: some View {
        VStack(spacing: T.Sp.s3) {
            Text("没有相机权限")
                .font(T.F.heading())
                .foregroundStyle(.white)
            Text("去「设置 → Workdeck → 相机」打开后再回来。")
                .font(T.F.small())
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("打开设置") {
                if let u = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(u)
                }
            }
            .font(T.F.small())
            .foregroundStyle(T.S.movingOnDark)
            .padding(.top, T.Sp.s2)
        }
        .padding(T.Sp.s8)
    }
}
