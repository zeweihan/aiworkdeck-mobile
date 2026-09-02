import SwiftUI

/// 字体与动效不是纯数据（含字重、弹簧参数），手写在这里；尺寸与时长引用生成的 T.Ty / T.Motion。
extension T {
    enum F {
        /// 只给关键数字
        static func hero() -> Font { .system(size: T.Ty.hero, weight: .light, design: .monospaced) }
        static func display() -> Font { .system(size: T.Ty.display, weight: .semibold) }
        static func title() -> Font { .system(size: T.Ty.title, weight: .semibold) }
        static func heading() -> Font { .system(size: T.Ty.heading, weight: .semibold) }
        static func body() -> Font { .system(size: T.Ty.body) }
        static func small() -> Font { .system(size: T.Ty.small) }
        static func micro() -> Font { .system(size: T.Ty.micro) }
        /// 全大写字距拉开的小标签。字距是这套排版的签名。
        static func nano() -> Font { .system(size: T.Ty.nano, weight: .medium) }
        /// 哈希、时间、坐标、计数一律等宽 —— 取证信息要能逐字符核对
        static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    /// 动效只用来表达「照片正在离开手机 / 在路上 / 已抵达」。不做装饰性动画。
    enum A {
        static let fast = Animation.easeOut(duration: T.Motion.fast)
        static let base = Animation.spring(response: 0.32, dampingFraction: 0.82)
        static let rise = Animation.spring(response: 0.42, dampingFraction: 0.86)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
