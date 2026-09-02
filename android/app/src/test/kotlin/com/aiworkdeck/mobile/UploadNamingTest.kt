package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.MediaKind
import com.aiworkdeck.mobile.model.TransferState
import com.aiworkdeck.mobile.services.UploadNaming
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class UploadNamingTest {
    private val at = Instant.parse("2026-09-02T09:05:07Z")

    @Test fun photoUsesMediaPrefixAndJpgExt() {
        val item = TestItems.make(TransferState.waiting, kind = MediaKind.photo, at = at)

        val name = UploadNaming.fileName(item, ZoneOffset.UTC)

        assertEquals("现场影像-20260902-090507-${item.id.take(4)}.jpg", name)
    }

    @Test fun videoUsesMediaPrefixAndMp4Ext() {
        val item = TestItems.make(TransferState.waiting, kind = MediaKind.video, at = at)

        val name = UploadNaming.fileName(item, ZoneOffset.UTC)

        assertEquals("现场影像-20260902-090507-${item.id.take(4)}.mp4", name)
    }

    @Test fun audioUsesAudioPrefixAndM4aExt() {
        val item = TestItems.make(TransferState.waiting, kind = MediaKind.audio, at = at)

        val name = UploadNaming.fileName(item, ZoneOffset.UTC)

        assertEquals("现场录音-20260902-090507-${item.id.take(4)}.m4a", name)
    }

    @Test fun idPrefixIsFirstFourCharsOfId() {
        val item = TestItems.make(TransferState.waiting, kind = MediaKind.photo, at = at)

        val name = UploadNaming.fileName(item, ZoneOffset.UTC)

        assertTrue(name.endsWith("-${item.id.take(4)}.jpg"))
        assertEquals(4, item.id.take(4).length)
    }
}
