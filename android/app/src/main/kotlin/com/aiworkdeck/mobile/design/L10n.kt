package com.aiworkdeck.mobile.design

import com.aiworkdeck.contract.ContractStrings

/** 契约文案。语言由 L10n.locale 决定，默认 zh-Hans（与 iOS 一致，英文待词典覆盖后再开）。缺键回显键名。 */
object L10n { @Volatile var locale: String = "zh-Hans" }

fun tr(key: String, vars: Map<String, Any> = emptyMap()): String {
    val entry = ContractStrings.table[key]
    var s = entry?.get("zh-Hans") ?: key
    if (L10n.locale != "zh-Hans") entry?.get(L10n.locale)?.takeIf { it.isNotEmpty() }?.let { s = it }
    for ((k, v) in vars) s = s.replace("{$k}", v.toString())
    return s
}
