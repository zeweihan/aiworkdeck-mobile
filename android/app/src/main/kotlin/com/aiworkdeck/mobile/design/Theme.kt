package com.aiworkdeck.mobile.design

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * 深色是否为「当前屏」的功能性深色（取景器、影像浏览），不是系统主题跟随。调用方按屏幕
 * 显式传 [dark]；组件读 [LocalOnDark] 决定用 `Tk.L` 还是 `Tk.D` / `*OnDark` 状态色。
 */
val LocalOnDark = staticCompositionLocalOf { false }

/**
 * Material3 在这里只当容器：只喂 colorScheme.background/onBackground，其余配色、字号、间距
 * 组件一律直读 [Tk]，不经 MaterialTheme 的 typography/shape。
 */
@Composable
fun WorkdeckTheme(dark: Boolean, content: @Composable () -> Unit) {
    val scheme = if (dark) {
        darkColorScheme(background = Tk.D.bg, onBackground = Tk.D.fg)
    } else {
        lightColorScheme(background = Tk.L.bg, onBackground = Tk.L.fg)
    }
    CompositionLocalProvider(LocalOnDark provides dark) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
