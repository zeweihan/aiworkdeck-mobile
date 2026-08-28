import SwiftUI

/// 首页 = 取景器。现场是单手、光线差、要快 —— 所以进来就是镜头，
/// 不再隔一层「按转盘进取景页」。信息各归其位：业务归属在顶部，
/// 画面在中间（淡水印叠加），快门与模式在拇指够得到的下方。
///
/// 水印只叠加在取景与展示层，**不烧录进照片字节**：
/// 照片是 JPEG 直出保 SHA-256「原始采集」，烧录会毁掉证据链（决策 D3）。
struct HomeView: View {
    /// 三档采集模式。photo/video 由相机会话承担，audio 走 AudioRecorderService——
    /// 录音本来就不该经过相机。三档并排显式给出，不藏在二级界面里。
    private enum CapMode: Hashable { case photo, video, audio }

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    /// 有全屏浮层（队列/影像/设置）压在上面时停相机省电；录像中除外，不能断录。
    let paused: Bool

    var onOpenLibrary: () -> Void
    var onOpenQueue: () -> Void
    var onOpenSettings: () -> Void

    @State private var camera = CameraService()
    @State private var recorder = AudioRecorderService()
    @State private var stamper = LocationStamper()
    @State private var mode: CapMode = .photo
    @State private var showFlash = false

    var body: some View {
        VStack(spacing: 0) {
            header
            stage
            controls
        }
        .background(T.D.bg.ignoresSafeArea())
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
            if mode != .audio { await camera.start() }
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
        .onChange(of: paused) { _, p in
            if p {
                if !camera.isRecording { camera.stop() }
            } else if mode != .audio {
                Task { await camera.start() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if !paused, mode != .audio { Task { await camera.start() } }
            case .background:
                // 录到一半退后台：停表并落库，不丢已录的内容——现场不可复现
                if recorder.isRecording { recorder.stop() }
                if camera.isRecording { Task { await camera.toggleRecording() } }
                camera.stop()
            default:
                break
            }
        }
    }

    // MARK: - 顶部信息

    private var header: some View {
        VStack(alignment: .leading, spacing: T.Sp.s1) {
            HStack {
                Eyebrow(text: "当前项目", color: .white.opacity(0.45))
                Spacer()
                locationChip
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: T.touchMin, height: 28, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("设置")
            }

            Text(model.project.name)
                .font(T.F.title())
                .kerning(-0.2)
                .foregroundStyle(T.D.fg)
                .lineLimit(1)

            Text("归档至 \(model.project.archivePath)")
                .font(T.F.nano())
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.4))

            tallyLine
                .padding(.top, T.Sp.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.Sp.gutter)
        .padding(.top, T.Sp.s2)
        .padding(.bottom, T.Sp.s3)
    }

    /// 位置精度：没有精度的坐标在质证时说明不了问题，所以直接显示出来
    private var locationChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stamper.last == nil ? Color.white.opacity(0.3) : T.S.arrivedOnDark)
                .frame(width: 5, height: 5)
            Text(stamper.last.map { "±\(Int($0.accuracy.rounded()))m" } ?? "定位中")
                .font(T.F.mono(10))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.trailing, T.Sp.s2)
    }

    private var tallyLine: some View {
        HStack(spacing: 0) {
            count(model.tally.waiting, "待传", T.S.waitingOnDark)
            divider
            count(model.tally.moving, "传输中", T.S.movingOnDark)
            divider
            count(model.tally.arrived, "已上传", T.S.arrivedOnDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenQueue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "待传 \(model.tally.waiting) 张，传输中 \(model.tally.moving) 张，已上传 \(model.tally.arrived) 张"
        )
        .accessibilityHint("查看上传队列")
        .accessibilityAddTraits(.isButton)
    }

    private func count(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(n)")
                .font(T.F.mono(13, .medium))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(T.F.nano())
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var divider: some View {
        Text("/")
            .font(T.F.micro())
            .foregroundStyle(.white.opacity(0.18))
            .padding(.horizontal, T.Sp.s2)
    }

    // MARK: - 取景舞台

    private var stage: some View {
        ZStack {
            if mode == .audio {
                audioStage
            } else if camera.permissionDenied {
                denied
            } else {
                CameraPreview(session: camera.session)
                    .overlay(alignment: .bottomLeading) { watermark }
            }

            // 快门白闪：唯一的「拍到了」即时反馈，比任何提示都快
            if showFlash {
                Color.white.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(T.D.rule, lineWidth: 1)
        }
        .padding(.horizontal, T.Sp.s2)
    }

    /// 淡水印：时间到秒、项目名、坐标与精度。白字低透明度加投影，
    /// 深浅背景都读得清，又不抢画面。只叠加显示，不写进照片。
    private var watermark: some View {
        VStack(alignment: .leading, spacing: 2) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Self.stamp(ctx.date))
                    .font(T.F.mono(12, .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
            Text(model.project.name)
                .font(T.F.micro())
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Text(coordLine)
                .font(T.F.mono(10))
                .foregroundStyle(.white.opacity(0.6))
        }
        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
        .padding(T.Sp.s3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var coordLine: String {
        guard let l = stamper.last else { return "GPS 定位中" }
        return String(format: "%.5f, %.5f · ±%.0fm", l.lat, l.lon, l.accuracy)
    }

    private static func stamp(_ d: Date) -> String {
        stampFormatter.string(from: d)
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - 底部控制

    private var controls: some View {
        VStack(spacing: T.Sp.s3) {
            if camera.isRecording || recorder.isRecording {
                HStack(spacing: T.Sp.s1) {
                    Circle().fill(T.S.failed).frame(width: 7, height: 7)
                    Text(timeString(camera.isRecording ? camera.recordingSeconds
                                                       : recorder.recordingSeconds))
                        .font(T.F.mono(13, .medium))
                        .foregroundStyle(.white)
                    Text(camera.isRecording ? "录像中" : "录音中")
                        .font(T.F.nano())
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(minHeight: 28)
            } else {
                modeRow
            }

            HStack {
                libraryEntry
                    .frame(maxWidth: .infinity, alignment: .leading)
                shutter
                counter
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Hairline(color: T.D.rule)

            HStack {
                HStack(spacing: T.Sp.s1) {
                    BreathingDot(isOn: model.link.isOnline, color: T.S.arrivedOnDark)
                    Text(linkCaption)
                        .font(T.F.nano())
                        .tracking(0.4)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text("SHA-256 · GPS · 时间戳")
                    .font(T.F.nano())
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, T.Sp.gutter)
        .padding(.top, T.Sp.s3)
        .padding(.bottom, T.Sp.s2)
    }

    /// 三档并排、点选切换。取证的模式必须显式可预期，
    /// 不做横滑模式条，也不做快门手势切换——手滑录错模式是取证事故。
    private var modeRow: some View {
        HStack(spacing: T.Sp.s8) {
            modeButton("照片", .photo)
            modeButton("录像", .video)
            modeButton("录音", .audio)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 28)
    }

    private func modeButton(_ label: String, _ m: CapMode) -> some View {
        Button {
            guard mode != m else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(T.A.fast) { mode = m }
        } label: {
            VStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 13, weight: mode == m ? .semibold : .regular))
                    .tracking(1)
                    .foregroundStyle(mode == m ? .white : .white.opacity(0.45))
                Circle()
                    .fill(.white)
                    .frame(width: 3, height: 3)
                    .opacity(mode == m ? 1 : 0)
            }
            .frame(minWidth: T.touchMin, minHeight: T.touchMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(mode == m ? [.isButton, .isSelected] : .isButton)
    }

    /// 最近一件的真缩略图，也是影像浏览的入口。
    private var libraryEntry: some View {
        Button(action: onOpenLibrary) {
            Group {
                if let last = model.items.first {
                    EvidenceThumb(item: last, onDark: true)
                        .overlay(alignment: .topLeading) {
                            StatusDot(state: last.state, size: 4, onDark: true)
                                .padding(3)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .stroke(T.D.rule, lineWidth: 1)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("最近影像，共 \(model.items.count) 张")
    }

    private var counter: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(model.tally.waiting + model.tally.moving + model.tally.arrived)")
                .font(T.F.mono(17, .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("本项目")
                .font(T.F.nano())
                .foregroundStyle(.white.opacity(0.5))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenQueue)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("查看上传队列")
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

    private var linkCaption: String {
        guard model.link.isOnline else {
            // 离线时说清楚已经等了多久 —— 照片悬在中转区这件事不能藏
            if let t = model.link.lastSyncedAt {
                return "桌面端离线 · 已等待 \(RelativeTime.short(t))"
            }
            return "桌面端离线"
        }
        if let t = model.link.lastSyncedAt {
            return "桌面端在线 · \(RelativeTime.short(t))"
        }
        return "桌面端在线"
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
        permissionStage(
            title: "没有麦克风权限",
            hint: "去「设置 → Workdeck → 麦克风」打开后再回来。"
        )
    }

    private var denied: some View {
        permissionStage(
            title: "没有相机权限",
            hint: "去「设置 → Workdeck → 相机」打开后再回来。"
        )
    }

    private func permissionStage(title: String, hint: String) -> some View {
        VStack(spacing: T.Sp.s3) {
            Text(title)
                .font(T.F.heading())
                .foregroundStyle(.white)
            Text(hint)
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

#Preview {
    HomeView(paused: false, onOpenLibrary: {}, onOpenQueue: {}, onOpenSettings: {})
        .environment(AppModel())
}
