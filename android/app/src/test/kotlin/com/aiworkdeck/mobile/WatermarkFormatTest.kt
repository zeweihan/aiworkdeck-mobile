package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.features.home.WatermarkFormat
import com.aiworkdeck.mobile.services.Loc
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class WatermarkFormatTest {

    @Test fun timeIsSecondPreciseInTheGivenZone() {
        val at = Instant.parse("2026-09-02T09:05:07Z")

        assertEquals("2026-09-02 09:05:07", WatermarkFormat.time(at, ZoneOffset.UTC))
        assertEquals("2026-09-02 17:05:07", WatermarkFormat.time(at, ZoneOffset.ofHours(8)))
    }

    @Test fun coordCarriesFiveDecimalsAndRoundedAccuracy() {
        val line = WatermarkFormat.coord(Loc(31.230581, 121.473702, 12.4))

        assertEquals("31.23058, 121.47370 · ±12 米", line)
    }

    @Test fun coordWithoutAccuracyOmitsTheAccuracyPart() {
        assertEquals("31.23058, 121.47370", WatermarkFormat.coord(Loc(31.230581, 121.473702, null)))
    }

    @Test fun noFixSaysLocatingRatherThanZeroZero() {
        assertEquals("定位中", WatermarkFormat.coord(null))
        assertEquals("定位中", WatermarkFormat.chip(null))
        assertEquals("定位中", WatermarkFormat.chip(Loc(31.0, 121.0, null)))
    }

    @Test fun durationIsMinutesAndSecondsPaddedToTwo() {
        assertEquals("00:00", WatermarkFormat.duration(0))
        assertEquals("00:05", WatermarkFormat.duration(5))
        assertEquals("01:07", WatermarkFormat.duration(67))
        assertEquals("75:00", WatermarkFormat.duration(4500))
        assertEquals("00:00", WatermarkFormat.duration(-3))
    }
}
