import SwiftUI

/// 影像浏览 —— 方向 B「影像优先」。
///
/// 深色，影像铺满，玻璃条压在影像上。这是全局唯一真正用得上毛玻璃的地方：
/// 玻璃需要下面有东西可透，压在纯色背景上等于白做。
struct LibraryView: View {
    let project: FieldProject
    let tally: TransferTally
    let link: DesktopLink
    let items: [CaptureItem]

    var onCapture: () -> Void
    var onClose: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [
        GridItem(.flexible(), spacing: 1.5),
        GridItem(.flexible(), spacing: 1.5),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            T.D.bg.ignoresSafeArea()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 1.5) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        cell(item)
                            .opacity(appeared || reduceMotion ? 1 : 0)
                            .offset(y: appeared || reduceMotion ? 0 : 10)
                            .animation(
                                T.A.rise.delay(Double(min(index, 12)) * 0.045),
                                value: appeared
                            )
                    }
                }
                // 顶栏与底座都是浮层，内容要自己让开，否则首末两行永远被压住
                .padding(.top, 96)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)

            topBar
        }
        .overlay(alignment: .bottom) { dock }
        .onAppear { appeared = true }
    }

    // MARK: - 单元格

    private func cell(_ item: CaptureItem) -> some View {
        ThumbPlaceholder(kind: item.kind, onDark: true)
            .aspectRatio(1, contentMode: .fill)
            .overlay(alignment: .topTrailing) {
                StatusDot(state: item.state, onDark: true)
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                Text(RelativeTime.clock(item.capturedAt))
                    .font(T.F.mono(10))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(8)
            }
            .overlay(alignment: .bottom) {
                if item.state == .moving {
                    // 进度直接画在图上。单独开一栏进度条会把注意力从影像上拉走。
                    GeometryReader { geo in
                        Rectangle()
                            .fill(T.S.movingOnDark)
                            .frame(width: geo.size.width * item.progress, height: 2)
                    }
                    .frame(height: 2)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(
                "\(kindLabel(item.kind))，\(RelativeTime.clock(item.capturedAt))，\(item.state.caption)"
            )
    }

    private func kindLabel(_ kind: MediaKind) -> String {
        switch kind {
        case .photo: "照片"
        case .video: "录像"
        case .audio: "录音"
        }
    }

    // MARK: - 顶栏（玻璃压在影像上）

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: T.Sp.s3) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(T.D.fg)
                        .frame(width: T.touchMin, height: T.touchMin)
                }
                .accessibilityLabel("返回")

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(T.F.heading())
                        .kerning(-0.2)
                        .foregroundStyle(T.D.fg)
                        .lineLimit(1)
                    tallyRow
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, T.Sp.s2)
            .padding(.trailing, T.Sp.gutter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, T.Sp.s2)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(alignment: .bottom) { Hairline(color: T.D.rule) }
                .ignoresSafeArea(edges: .top)
        }
    }

    private var tallyRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            pill(tally.waiting, "待传", T.S.waitingOnDark)
            pill(tally.moving, "传输中", T.S.movingOnDark)
            pill(tally.arrived, "已上传", T.S.arrivedOnDark)
        }
        .accessibilityElement(children: .combine)
    }

    private func pill(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Text("\(n)")
                .font(T.F.mono(13, .medium))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(T.F.nano())
                .foregroundStyle(T.D.fgMuted)
        }
        .padding(.trailing, T.Sp.s2)
    }

    // MARK: - 底座与快门

    private var dock: some View {
        HStack {
            HStack(spacing: T.Sp.s1) {
                BreathingDot(isOn: link.isOnline, color: T.S.arrivedOnDark)
                Text(link.isOnline ? "桌面端在线" : "桌面端离线")
                    .font(T.F.nano())
                    .tracking(0.6)
                    .foregroundStyle(T.D.fgMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShutterButton(action: onCapture)

            Text(project.archivePath)
                .font(T.F.nano())
                .tracking(0.6)
                .foregroundStyle(T.D.fgMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, T.Sp.gutter)
        .padding(.top, T.Sp.s3)
        .padding(.bottom, T.Sp.s2)
        .background {
            LinearGradient(
                colors: [T.D.bg.opacity(0), T.D.bg.opacity(0.94)],
                startPoint: .top, endPoint: .bottom
            )
            .background(.ultraThinMaterial.opacity(0.6))
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// 物理相机的快门语汇：外环加内芯，按下内芯收缩。不用图标。
private struct ShutterButton: View {
    let action: () -> Void

    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.85), lineWidth: 1.5)
            Circle()
                .fill(.white)
                .frame(width: 52, height: 52)
                .scaleEffect(pressed && !reduceMotion ? 0.86 : 1)
                .animation(T.A.fast, value: pressed)
        }
        .frame(width: 66, height: 66)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
        .accessibilityLabel("拍摄")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    LibraryView(
        project: DemoData.project,
        tally: DemoData.tally,
        link: DemoData.link,
        items: DemoData.recent,
        onCapture: {},
        onClose: {}
    )
}
