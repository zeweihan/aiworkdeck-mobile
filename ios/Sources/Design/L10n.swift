import Foundation

/// 契约文案。语言由 L10n.locale 决定，默认 zh-Hans（大陆版永远中文，测试与模拟器语言无关）。
/// configureFromDevice() 暂未接线（见 WorkdeckApp 的注释）：接线后设备语言非中文且 en 非空时才用 en。
enum L10n {
    nonisolated(unsafe) static var locale: String = "zh-Hans"

    static func configureFromDevice() {
        let preferZh = (Locale.preferredLanguages.first ?? "zh").hasPrefix("zh")
        locale = preferZh ? "zh-Hans" : "en"
    }
}

func tr(_ key: String, _ vars: [String: String] = [:]) -> String {
    let entry = ContractStrings.table[key]
    var s = entry?["zh-Hans"] ?? key
    if L10n.locale != "zh-Hans", let v = entry?[L10n.locale], !v.isEmpty { s = v }
    for (k, v) in vars { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
    return s
}
