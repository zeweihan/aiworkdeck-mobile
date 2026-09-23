import Foundation
import Observation

/// 当前界面语言，可观察：SwiftUI 的 body 里调 `tr()` 会读到它，语言一变所有可见界面自动重绘，
/// 不用逐页挂刷新。写入只在主线程（启动时、登录页切区域时）；读可以来自任何隔离域
/// （上传队列、API 的报错文案），所以标成 @unchecked Sendable。
@Observable
final class L10nState: @unchecked Sendable {
    var locale: String = "zh-Hans"
}

/// 契约文案。语言**跟账号区域走**（dev-board#837）：大陆版 zh-Hans，海外版 en。
/// 不跟设备语言——海外版就是给境外用户的，大陆版用户的手机设成英文也照样是中文站的账号。
enum L10n {
    static let state = L10nState()

    static var locale: String {
        get { state.locale }
        set { state.locale = newValue }
    }

    // 区域 → 语言的映射（locale(for:) / apply(region:)）写在 Backend.swift 的 extension 里：
    // 这份文件也编进 Live Activity 扩展，扩展里没有 AccountRegion。

    /// 日期格式化用的 Locale（月份名、日序跟着界面语言走，不跟设备）。
    static var formatLocale: Locale {
        Locale(identifier: locale == "en" ? "en_US" : "zh_CN")
    }
}

/// `locale` 缺省取当前界面语言；Live Activity 扩展是另一个进程，拿不到 App 的语言状态，
/// 由活动属性把开始录音那一刻的语言带过去再显式传进来。
func tr(_ key: String, _ vars: [String: String] = [:], locale: String? = nil) -> String {
    let entry = ContractStrings.table[key]
    var s = entry?["zh-Hans"] ?? key
    let locale = locale ?? L10n.locale
    if locale != "zh-Hans", let v = entry?[locale], !v.isEmpty { s = v }
    for (k, v) in vars { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
    return s
}
