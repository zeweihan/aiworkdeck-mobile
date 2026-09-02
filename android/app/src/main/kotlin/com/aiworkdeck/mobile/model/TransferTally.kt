package com.aiworkdeck.mobile.model

data class TransferTally(val uploading: Int, val failed: Int, val staged: Int, val landed: Int) {
    val total: Int get() = uploading + staged + landed
    companion object {
        val zero = TransferTally(0, 0, 0, 0)
        fun of(items: List<CaptureItem>): TransferTally {
            var u = 0; var f = 0; var s = 0; var l = 0
            for (i in items) {
                when (i.state.phase) { TransferPhase.uploading -> u++; TransferPhase.staged -> s++; TransferPhase.landed -> l++ }
                if (i.state == TransferState.failed) f++
            }
            return TransferTally(u, f, s, l)
        }
    }
}
