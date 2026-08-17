import SwiftUI

/// 首页 —— 方向 C「仪器极简」。
///
/// 现场是单手、光线差、要快。所以只给一个巨大的、闭着眼睛都能按到的控件，
/// 其余信息全部退到极小。信息不消失，只是不喊。
struct HomeView: View {
    let project: FieldProject
    let tally: TransferTally
    let link: DesktopLink
    let recent: [CaptureItem]

    var onCapture: () -> Void
    var onOpenLibrary: () -> Void
    var onOpenQueue: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            dialStage
            Spacer(minLength: 0)
            footer
        }
        .background(T.L.bg)
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: T.Sp.s2) {
            HStack {
                Eyebrow(text: "当前项目")
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(T.L.fgFaint)
                        .frame(width: T.touchMin, height: 28, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("设置")
            }

            Text(project.name)
                .font(T.F.title())
                .kerning(-0.2)
                .foregroundStyle(T.L.fg)
                .lineLimit(1)

            tallyLine
                .padding(.top, T.Sp.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.Sp.gutter)
        .padding(.top, T.Sp.s6)
    }

    /// 一行等宽的计数。不做并排大彩色数字 —— 那是财务报表。
    private var tallyLine: some View {
        HStack(spacing: 0) {
            count(tally.waiting, "待传", T.S.waiting)
            divider
            count(tally.moving, "传输中", T.S.moving)
            divider
            count(tally.arrived, "已上传", T.S.arrived)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenQueue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "待传 \(tally.waiting) 张，传输中 \(tally.moving) 张，已上传 \(tally.arrived) 张"
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
                .foregroundStyle(T.L.fgFaint)
        }
    }

    private var divider: some View {
        Text("/")
            .font(T.F.micro())
            .foregroundStyle(T.L.ruleStrong)
            .padding(.horizontal, T.Sp.s2)
    }

    // MARK: - 主控件
    /// 留白是设计的一部分，不要压缩。

    private var dialStage: some View {
        VStack(spacing: 0) {
            ShutterDial(action: onCapture)

            Text("拍摄")
                .font(T.F.heading())
                .kerning(3.8)                 // 字距是这套设计的签名
                .padding(.leading, 3.8)       // 补掉尾字距造成的视觉偏左
                .foregroundStyle(T.L.fg)
                .padding(.top, T.Sp.s6)

            Text("归档至 \(project.archivePath)")
                .font(T.F.micro())
                .foregroundStyle(T.L.fgFaint)
                .padding(.top, T.Sp.s1)
        }
        .padding(.vertical, T.Sp.s10)
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 0) {
            thumbStrip
                .padding(.horizontal, T.Sp.gutter)
                .padding(.bottom, T.Sp.s5)

            Hairline()

            HStack {
                HStack(spacing: T.Sp.s1) {
                    BreathingDot(isOn: link.isOnline)
                    Text(linkCaption)
                        .font(T.F.nano())
                        .tracking(0.4)
                        .foregroundStyle(T.L.fgMuted)
                }
                Spacer()
                Text("SHA-256 · GPS · 时间戳")
                    .font(T.F.nano())
                    .tracking(0.4)
                    .foregroundStyle(T.L.fgFaint)
            }
            .padding(.horizontal, T.Sp.gutter)
            .padding(.top, T.Sp.s3)
        }
        .padding(.bottom, T.Sp.s8)
    }

    private var linkCaption: String {
        guard link.isOnline else {
            // 离线时说清楚已经等了多久 —— 照片悬在中转区这件事不能藏
            if let t = link.lastSyncedAt {
                return "桌面端离线 · 已等待 \(RelativeTime.short(t))"
            }
            return "桌面端离线"
        }
        if let t = link.lastSyncedAt {
            return "桌面端在线 · \(RelativeTime.short(t))"
        }
        return "桌面端在线"
    }

    private var thumbStrip: some View {
        // 用 LazyVGrid 的等分列，不用 HStack + aspectRatio(.fit)：
        // Rectangle 与 Text 在 HStack 里争宽度时，aspectRatio(.fit) 会把
        // 缩略图压成几乎零宽，界面上只剩一排状态点。踩过一次。
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: T.Sp.s1), count: 6),
            spacing: T.Sp.s1
        ) {
            ForEach(recent.prefix(5)) { item in
                ThumbPlaceholder(kind: item.kind)
                    .aspectRatio(1, contentMode: .fill)
                    .overlay(alignment: .topLeading) {
                        StatusDot(state: item.state, size: 4)
                            .padding(3)
                    }
            }

            let rest = max(tally.arrived + tally.waiting + tally.moving - 5, 0)
            if rest > 0 {
                // 用 Color.clear 撑出方格再叠字，不要直接给 Text 加 aspectRatio：
                // Text 有固有高度，aspectRatio 会照它算，结果这一格比邻居矮一截。
                Color.clear
                    .aspectRatio(1, contentMode: .fill)
                    .overlay {
                        Text("+\(rest)")
                            .font(T.F.mono(10))
                            .foregroundStyle(T.L.fgMuted)
                    }
                    .background(T.L.sunken)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(T.L.rule, lineWidth: 1)
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenLibrary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近影像，共 \(recent.count) 张")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 快门转盘

/// Braun 的语汇：一个主控件，细而准的外环，四个刻度，中心一圈镜头环。
/// 这条外环的粗细决定了整个界面的精度感。
private struct ShutterDial: View {
    let action: () -> Void

    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 210
    private let coreSize: CGFloat = 150

    var body: some View {
        ZStack {
            Circle()
                .stroke(T.L.ruleStrong, lineWidth: 1)
                .frame(width: size, height: size)

            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(T.L.ruleStrong)
                    .frame(width: 1, height: 8)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(Double(i) * 90))
            }

            Circle()
                .fill(T.L.fg)
                .frame(width: coreSize, height: coreSize)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        .frame(width: 58, height: 58)
                }
                .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
                .animation(T.A.base, value: pressed)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: fire)
        .accessibilityElement()
        .accessibilityLabel("拍摄")
        .accessibilityHint("拍摄的影像会自动归入今天的现场影像")
        .accessibilityAddTraits(.isButton)
    }

    private func fire() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        action()
    }
}

#Preview {
    HomeView(
        project: DemoData.project,
        tally: DemoData.tally,
        link: DemoData.link,
        recent: DemoData.recent,
        onCapture: {},
        onOpenLibrary: {},
        onOpenQueue: {},
        onOpenSettings: {}
    )
}
