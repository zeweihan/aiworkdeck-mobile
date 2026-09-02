package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.design.L10n
import com.aiworkdeck.mobile.design.tr
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

class L10nTest {
    @After fun resetLocale() { L10n.locale = "zh-Hans" }

    @Test fun substitutesPlaceholders() {
        assertEquals("未知项目", tr("library.unknownProject"))
        assertEquals("9月2日 · 3 件", tr("library.dayTitle", mapOf("m" to 9, "d" to 2, "n" to 3)))
    }

    @Test fun missingKeyEchoesKeyName() {
        assertEquals("no.such.key", tr("no.such.key"))
    }

    @Test fun localeSwitchesToEnglishAndBack() {
        L10n.locale = "en"
        assertEquals("Unknown project", tr("library.unknownProject"))
        L10n.locale = "zh-Hans"
        assertEquals("未知项目", tr("library.unknownProject"))
    }
}
