package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.features.queue.expiryDaysLeft
import com.aiworkdeck.mobile.features.settings.formatBytes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class SettingsFormatTest {
    @Test fun formatsBytesWithBinaryStepsAndOneDecimalUnderTen() {
        assertEquals("0 B", formatBytes(0))
        assertEquals("512 B", formatBytes(512))
        assertEquals("1.5 KB", formatBytes(1536))
        assertEquals("2.0 GB", formatBytes(2L * 1024 * 1024 * 1024))
    }

    @Test fun dropsDecimalOnceTheNumberIsBigEnoughToBeNoise() {
        assertEquals("300 MB", formatBytes(300L * 1024 * 1024))
        // 负数只可能是服务端给了脏值，按 0 显示而不是画出个「-1 B」
        assertEquals("0 B", formatBytes(-1))
    }

    @Test fun expiryDaysRoundUpAndClampAtZero() {
        val now = Instant.parse("2026-09-03T00:00:00Z")
        assertEquals(3L, expiryDaysLeft("2026-09-05T18:00:00Z", now))
        assertEquals(1L, expiryDaysLeft("2026-09-03T01:00:00Z", now))
        assertEquals(0L, expiryDaysLeft("2026-09-02T23:00:00Z", now))
        assertNull(expiryDaysLeft(null, now))
        assertNull(expiryDaysLeft("不是时间", now))
    }
}
