package com.aiworkdeck.mobile.model

import com.aiworkdeck.contract.ContractStates
import com.aiworkdeck.mobile.design.tr

data class StatusMerge(val state: TransferState, val waitingSeconds: Long?, val expiresAt: String?)

enum class TransferEvent(val raw: String) {
    kick("kick"), http2xx("http_2xx"), httpError("http_error"), networkError("network_error"),
    retryManual("retry_manual"), retryAuto("retry_auto"), statusDelivered("status_delivered"),
    statusPending("status_pending"), appLaunch("app_launch")
}

enum class TransferPhase(val raw: String) {
    uploading("uploading"), staged("staged"), landed("landed");
    val caption: String get() = tr(ContractStates.phaseLabelKey.getValue(raw))
    companion object { fun fromRaw(s: String) = entries.first { it.raw == s } }
}

/** 一张影像在「拍摄 → 抵达电脑」链上的位置。名称、别名、映射、文案键全部来自 ContractStates。 */
enum class TransferState(val raw: String) {
    waiting("waiting"), uploading("uploading"), uploaded("uploaded"), arrived("arrived"), failed("failed");

    val phase: TransferPhase get() = TransferPhase.fromRaw(ContractStates.phaseOf.getValue(raw))
    val caption: String get() = tr(ContractStates.stateTextKey.getValue(raw))
    val detail: String get() = tr(ContractStates.stateDetailKey.getValue(raw))
    val whereItIs: String get() = tr(ContractStates.whereKey.getValue(raw))

    /** 迁移表驱动。无规则 → null（非法迁移）；有规则但 guard 不满足 → 原态。 */
    fun next(event: TransferEvent, attempts: Int = 0): TransferState? {
        val rules = ContractStates.transitions.filter { it.from == raw && it.event == event.raw }
        if (rules.isEmpty()) return null
        for (r in rules) if (guardOk(r.guard, attempts)) return fromRaw(r.to) ?: error("契约迁移目标未知: ${r.to}")
        return this
    }

    /** 冷启动回拨 = app_launch 事件。 */
    fun recovered(attempts: Int = 0): TransferState = next(TransferEvent.appLaunch, attempts) ?: this

    /** status 轮询只对 uploaded 有意义；delivered 清掉等待字段，pending 回填。 */
    fun applyingStatus(delivered: Boolean, waitingSeconds: Long, expiresAt: String?): StatusMerge {
        if (this != uploaded) return StatusMerge(this, null, null)
        return if (delivered) StatusMerge(next(TransferEvent.statusDelivered) ?: this, null, null)
        else StatusMerge(next(TransferEvent.statusPending) ?: this, waitingSeconds, expiresAt)
    }

    companion object {
        /** 旧值（如 moving）按契约别名解码；编码始终用正式名。 */
        fun fromRaw(s: String): TransferState? {
            val canonical = ContractStates.aliases[s] ?: s
            return entries.firstOrNull { it.raw == canonical }
        }
        private fun guardOk(guard: String?, attempts: Int): Boolean = when (guard) {
            null -> true
            "attempts <= maxAutoRetries" -> attempts <= ContractStates.maxAutoRetries
            else -> error("未知 guard: $guard")
        }
    }
}
