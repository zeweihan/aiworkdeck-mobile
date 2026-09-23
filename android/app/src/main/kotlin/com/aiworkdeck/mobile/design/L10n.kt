package com.aiworkdeck.mobile.design

import androidx.compose.runtime.mutableStateOf
import com.aiworkdeck.contract.ContractStrings
import com.aiworkdeck.mobile.services.AccountRegion

/**
 * 契约文案。语言由 L10n.locale 决定，跟着账号区域走（大陆版 zh-Hans、海外版 en，dev-board#837）。缺键回显键名。
 *
 * locale 放在 Compose 快照状态里：界面里每处 tr() 都读了它，换语言时读过它的界面自动重绘，
 * 不用逐屏通知。非界面调用（通知、Worker）读到的就是当下的值。
 */
object L10n {
    private val state = mutableStateOf("zh-Hans")
    var locale: String
        get() = state.value
        set(value) { state.value = value }

    /** 启动时与登录页切区域时调：界面语言跟随区域。 */
    fun follow(region: AccountRegion) { locale = region.locale }
}

fun tr(key: String, vars: Map<String, Any> = emptyMap()): String {
    val entry = ContractStrings.table[key]
    var s = entry?.get("zh-Hans") ?: key
    if (L10n.locale != "zh-Hans") entry?.get(L10n.locale)?.takeIf { it.isNotEmpty() }?.let { s = it }
    for ((k, v) in vars) s = s.replace("{$k}", v.toString())
    return s
}
