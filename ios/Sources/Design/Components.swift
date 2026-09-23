import SwiftUI

/// 全大写、字距拉开的小标签。这套排版的签名，三个界面共用。
struct Eyebrow: View {
    let text: String
    var color: Color = T.L.fgFaint

    var body: some View {
        Text(text)
            .font(T.F.nano())
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// 发丝线。分区靠它，不靠卡片。
///
/// 用 1pt 而不是 1/scale 的物理像素：iOS 系统分隔线就是 1pt，
/// 亚像素线在深色底上会因为抗锯齿变灰、看着脏。
struct Hairline: View {
    var color: Color = T.L.rule
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

/// 状态点。色只做点，不做块。
struct StatusDot: View {
    let state: TransferState
    var size: CGFloat = 5
    var onDark: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }

    private var color: Color {
        switch state {
        // 排队与传输都是「还在手机上」：一个颜色，别让用户猜串行队列的内部细节
        case .waiting, .uploading: onDark ? T.S.waitingOnDark : T.S.waiting
        // 已暂存：进了中转区但还没到电脑，绿点会撒谎
        case .uploaded: onDark ? T.S.movingOnDark : T.S.moving
        case .arrived: onDark ? T.S.arrivedOnDark : T.S.arrived
        case .failed: T.S.failed
        }
    }
}

/// 在线呼吸点。唯一一处循环动画 —— 它表示「连接是活的」，承载语义。
struct BreathingDot: View {
    var isOn: Bool
    var color: Color = T.S.arrived

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(isOn ? color : T.L.fgFaint)
            .frame(width: 4, height: 4)
            .overlay {
                if isOn && !reduceMotion {
                    Circle()
                        .stroke(color.opacity(expanded ? 0 : 0.45), lineWidth: 3)
                        .scaleEffect(expanded ? 3.2 : 1)
                }
            }
            .onAppear {
                guard isOn, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) {
                    expanded = true
                }
            }
    }
}

/// 占位缩略图。接真图后换成 `Image`，圆角与比例保持不变。
/// 近乎直角是刻意的 —— 圆角是「App 感」，直角是「文档感」。
struct ThumbPlaceholder: View {
    let kind: MediaKind
    var onDark: Bool = false

    var body: some View {
        Rectangle()
            .fill(fill)
            .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
    }

    private var fill: LinearGradient {
        let pair: (Color, Color) = switch (onDark, kind) {
        // 东方清雅体系（dev-board#731 #732 #733）：暖中性为底，三种媒体类型靠竹月青/浅茶金做极浅色相区分。
        case (true, .photo): (Color(hex: 0x2B2721), Color(hex: 0x201C17))
        case (true, .video): (Color(hex: 0x272E28), Color(hex: 0x1B211C))
        case (true, .audio): (Color(hex: 0x2E2820), Color(hex: 0x201A13))
        case (false, .photo): (Color(hex: 0xEDEAE0), Color(hex: 0xE6E1D3))
        case (false, .video): (Color(hex: 0xE6EBE3), Color(hex: 0xDCE4DC))
        case (false, .audio): (Color(hex: 0xF0EAE0), Color(hex: 0xE9E0D2))
        }
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 相对时间，用于「12 秒前同步」。
enum RelativeTime {
    static func short(_ date: Date, now: Date = .now) -> String {
        let s = Int(now.timeIntervalSince(date))
        return switch s {
        case ..<60: tr("time.secondsAgo", ["n": String(max(s, 0))])
        case ..<3600: tr("time.minutesAgo", ["n": String(s / 60)])
        case ..<86400: tr("time.hoursAgo", ["n": String(s / 3600)])
        default: tr("time.daysAgo", ["n": String(s / 86400)])
        }
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
