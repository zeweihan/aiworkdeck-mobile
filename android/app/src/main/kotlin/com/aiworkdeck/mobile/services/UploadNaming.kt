package com.aiworkdeck.mobile.services

import com.aiworkdeck.mobile.design.tr
import com.aiworkdeck.mobile.model.CaptureItem
import com.aiworkdeck.mobile.model.MediaKind
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * 上传文件名。镜像 iOS UploadQueue.fileName(for:)：带上采集时刻，桌面端按名字排序即是时间序；
 * 不用原始 UUID 当名字——律师在文件夹里看到一串十六进制没有任何意义。
 */
object UploadNaming {
    private val stamp = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")

    fun fileName(item: CaptureItem, zone: ZoneId = ZoneId.systemDefault()): String {
        val prefix = when (item.kind) {
            MediaKind.photo, MediaKind.video -> tr("file.prefix.media")
            MediaKind.audio -> tr("file.prefix.audio")
        }
        val time = stamp.format(item.capturedAt.atZone(zone))
        val short = item.id.take(4)
        return "$prefix-$time-$short.${item.kind.ext}"
    }
}
