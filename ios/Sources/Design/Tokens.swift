import SwiftUI

/// 设计令牌 —— 与 `miniprogram/styles/tokens.wxss` 逐值对应。
///
/// 双模：拍摄与影像浏览走深色（器械感 + 真玻璃），其余走浅色（与桌面端同调）。
/// 浅色侧的底是纯白，不是浅灰 —— 浅灰底加白卡片加阴影是后台仪表盘语汇。
/// 分区靠发丝线与留白，层级靠字级跨度，不靠颜色。
///
/// 改这里必须同步 tokens.wxss，两边由 scripts/check-tokens.mjs 对拍。
enum T {

    // MARK: - 浅色（项目、文件、设置）

    enum L {
        static let bg = Color(hex: 0xFFFFFF)
        static let sunken = Color(hex: 0xFAFAFA)
        static let fg = Color(hex: 0x0A0E1A)          // 近黑，不是纯黑
        static let fgMuted = Color(hex: 0x6B7280)
        static let fgFaint = Color(hex: 0x9CA3AF)
        static let rule = Color(hex: 0xECEEF1)
        static let ruleStrong = Color(hex: 0xD4D8DE)
        /// 藏青只作强调，用量极小。用多了就回到"企业蓝"的俗气里。
        static let accent = Color(hex: 0x1E3A8A)
        static let accentWash = Color(hex: 0xF4F6FB)
    }

    // MARK: - 深色（取景、影像浏览）

    enum D {
        static let bg = Color(hex: 0x0A0B0D)
        static let surface = Color(hex: 0x141619)
        static let fg = Color(hex: 0xF5F6F7)
        static let fgMuted = Color(hex: 0x8A8F98)
        static let rule = Color.white.opacity(0.10)
    }

    // MARK: - 状态
    /// 这个 App 的主线叙事就是「照片在哪」。
    /// 但状态色只做小圆点与小字，绝不做大块彩色数字 —— 那是财务报表。

    enum S {
        static let waiting = Color(hex: 0xC2410C)   // 在手机上
        static let moving = Color(hex: 0x1E3A8A)    // 在路上
        static let arrived = Color(hex: 0x15803D)   // 已归档
        static let failed = Color(hex: 0xB91C1C)

        /// 深色底上的同一组语义色，提亮以保住对比度
        static let waitingOnDark = Color(hex: 0xF97316)
        static let movingOnDark = Color(hex: 0x60A5FA)
        static let arrivedOnDark = Color(hex: 0x4ADE80)
    }

    // MARK: - 间距（wxss 的 rpx ÷ 2）

    enum Sp {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let s10: CGFloat = 40
        static let s16: CGFloat = 64
        /// 页面左右边距，与 iOS 系统列表一致
        static let gutter: CGFloat = 20
    }

    // MARK: - 字号
    /// 层级靠字级跨度拉开，不靠颜色。

    enum F {
        /// 只给关键数字
        static func hero() -> Font { .system(size: 44, weight: .light, design: .monospaced) }
        static func display() -> Font { .system(size: 30, weight: .semibold) }
        static func title() -> Font { .system(size: 21, weight: .semibold) }
        static func heading() -> Font { .system(size: 16, weight: .semibold) }
        static func body() -> Font { .system(size: 15) }
        static func small() -> Font { .system(size: 13) }
        static func micro() -> Font { .system(size: 11) }
        /// 全大写字距拉开的小标签。字距是这套排版的签名。
        static func nano() -> Font { .system(size: 10, weight: .medium) }

        /// 哈希、时间、坐标、计数一律等宽 —— 取证信息要能逐字符核对
        static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // MARK: - 动效
    /// 动效只用来表达「照片正在离开手机 / 在路上 / 已抵达」。不做装饰性动画。

    enum A {
        static let fast = Animation.easeOut(duration: 0.14)
        static let base = Animation.spring(response: 0.32, dampingFraction: 0.82)
        static let rise = Animation.spring(response: 0.42, dampingFraction: 0.86)
    }

    /// 触控最小 44pt 是硬指标，不是建议
    static let touchMin: CGFloat = 44
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
