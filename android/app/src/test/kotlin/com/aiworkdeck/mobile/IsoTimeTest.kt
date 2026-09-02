package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.IsoTime
import org.junit.Assert.*
import org.junit.Test
import java.time.ZoneId
import java.time.ZoneOffset

class IsoTimeTest {
    @Test fun parsesOffsetForm() {
        val i = IsoTime.parse("2026-09-02T17:00:00+08:00")
        assertNotNull(i)
        assertEquals("2026-09-02T09:00:00Z", i.toString())
    }

    @Test fun parsesLocalFormWithoutOffset() {
        val zone = ZoneOffset.UTC
        val i = IsoTime.parse("2026-09-02T17:00:00", zone)
        assertNotNull(i)
        assertEquals("2026-09-02T17:00:00Z", i.toString())
    }

    @Test fun parsesFractionalSecondsWithZ() {
        val i = IsoTime.parse("2026-09-02T17:00:00.123Z")
        assertNotNull(i)
        assertEquals("2026-09-02T17:00:00.123Z", i.toString())
    }

    @Test fun formatRoundTripsThroughParse() {
        val zone = ZoneId.of("Asia/Shanghai")
        val formatted = IsoTime.format(java.time.Instant.parse("2026-09-02T09:00:00Z"), zone)
        assertEquals("2026-09-02T17:00:00+08:00", formatted)
        assertEquals(java.time.Instant.parse("2026-09-02T09:00:00Z"), IsoTime.parse(formatted, zone))
    }
}
