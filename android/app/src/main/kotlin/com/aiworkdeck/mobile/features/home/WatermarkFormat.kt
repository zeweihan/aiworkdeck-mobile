package com.aiworkdeck.mobile.features.home

import com.aiworkdeck.mobile.design.tr
import com.aiworkdeck.mobile.services.Loc
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * 水印与定位芯片的纯格式化。抽出来是为了能在 JVM 单测里直接对拍——秒级时间与坐标精度
 * 是取证信息，格式错了不该等到人肉走查才发现。
 *
 * 与 iOS `HomeView.stamp` / `coordLine` 同格式：时间到秒，坐标五位小数（约 1 米量级）。
 */
object WatermarkFormat {
    private val stamp = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")

    fun time(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): String = stamp.format(instant.atZone(zone))

    /** 水印上的坐标行。没有定位就说「定位中」——不写零零坐标，那是在编。 */
    fun coord(loc: Loc?): String {
        if (loc == null) return tr("home.gps.none")
        val base = String.format(Locale.US, "%.5f, %.5f", loc.lat, loc.lon)
        val acc = loc.accuracy ?: return base
        return "$base · ${accuracy(acc)}"
    }

    /** 顶部芯片：只给精度。没有精度的坐标在质证时说明不了问题，所以精度要直接显示出来。 */
    fun chip(loc: Loc?): String {
        val acc = loc?.accuracy ?: return tr("home.gps.none")
        return accuracy(acc)
    }

    private fun accuracy(meters: Double): String = tr("home.gps.accuracy", mapOf("m" to Math.round(meters)))

    /** 录制计时 mm:ss。超过一小时也继续往上加分钟，不进位到小时——现场没有那么长的单段。 */
    fun duration(seconds: Long): String {
        val s = seconds.coerceAtLeast(0)
        return String.format(Locale.US, "%02d:%02d", s / 60, s % 60)
    }
}
