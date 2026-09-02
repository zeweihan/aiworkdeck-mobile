package com.aiworkdeck.mobile.features.settings

import java.util.Locale

private val UNITS = arrayOf("B", "KB", "MB", "GB", "TB")

/**
 * 字节数给人看。1024 进位（与 iOS `ByteCountFormatter.countStyle = .binary` 同口径，
 * 两端显示同一个配额时不会差出 5%）。小于 10 保留一位小数，10 以上取整——
 * 「4.7 GB / 20 GB」有用，「4.73 GB」只是噪音。
 *
 * 纯函数，不碰 Android，JVM 单测直接调。
 */
fun formatBytes(bytes: Long): String {
    var v = bytes.coerceAtLeast(0L).toDouble()
    var i = 0
    while (v >= 1024.0 && i < UNITS.size - 1) { v /= 1024.0; i++ }
    val n = if (i == 0) v.toLong().toString()
    else String.format(Locale.US, if (v < 10.0) "%.1f" else "%.0f", v)
    return "$n ${UNITS[i]}"
}
