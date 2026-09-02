package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.TransferEvent
import com.aiworkdeck.mobile.model.TransferState
import org.junit.Assert.*
import org.junit.Test

class TransferStateTest {
    @Test fun fromRawDecodesCanonicalNames() {
        for (s in TransferState.entries) assertEquals(s, TransferState.fromRaw(s.raw))
    }

    @Test fun fromRawDecodesLegacyAlias() {
        assertEquals(TransferState.uploading, TransferState.fromRaw("moving"))
    }

    @Test fun fromRawUnknownReturnsNull() {
        assertNull(TransferState.fromRaw("does-not-exist"))
    }

    @Test fun nextReturnsNullForIllegalTransition() {
        assertNull(TransferState.arrived.next(TransferEvent.kick))
        assertNull(TransferState.waiting.next(TransferEvent.http2xx))
    }

    @Test fun nextGuardBoundaryOnRetryAuto() {
        // maxAutoRetries = 3：attempts <= 3 通过，attempts = 4 失败 → 原态
        assertEquals(TransferState.waiting, TransferState.failed.next(TransferEvent.retryAuto, 3))
        assertEquals(TransferState.failed, TransferState.failed.next(TransferEvent.retryAuto, 4))
    }

    @Test fun recoveredFallsBackToSelfWhenNoRule() {
        // uploaded 没有 app_launch 迁移规则 → recovered 回落到自身
        assertEquals(TransferState.uploaded, TransferState.uploaded.recovered())
    }
}
