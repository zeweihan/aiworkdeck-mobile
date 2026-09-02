package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.*
import java.io.File
import java.time.Instant
import java.util.UUID

object TestItems {
    fun make(state: TransferState, project: RelayProject? = null, at: Instant = Instant.now(), kind: MediaKind = MediaKind.photo): CaptureItem {
        val id = UUID.randomUUID().toString().lowercase()
        return CaptureItem(id = id, kind = kind, state = state,
            manifest = CaptureManifest(clientMediaId = id, sha256 = "a".repeat(64), capturedAt = IsoTime.format(at),
                serverReceivedAt = null, latitude = null, longitude = null, horizontalAccuracy = null,
                deviceModel = "x", osVersion = "x", appVersion = "x", fromCamera = true, tsaToken = null),
            localFile = File("/dev/null"), progress = 0.0, lastError = null, savedToAlbum = false, project = project)
    }
}
