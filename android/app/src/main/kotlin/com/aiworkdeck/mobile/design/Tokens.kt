package com.aiworkdeck.mobile.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.aiworkdeck.contract.T

/**
 * `com.aiworkdeck.contract.T` 转成 Compose 类型：颜色 ARGB `Long` → `Color`，间距 `Int`(dp) → `Dp`，
 * 字号 `Int`(sp) → `TextUnit`。逐字段手写，不用反射——契约改了字段这里编译不过，比运行时漏映射早发现。
 */
object Tk {
    /** 浅色（主界面之外大多数屏）。底是纯白不是浅灰。 */
    object L {
        val bg: Color = Color(T.L.bg)
        val sunken: Color = Color(T.L.sunken)
        val fg: Color = Color(T.L.fg)
        val fgMuted: Color = Color(T.L.fgMuted)
        val fgFaint: Color = Color(T.L.fgFaint)
        val rule: Color = Color(T.L.rule)
        val ruleStrong: Color = Color(T.L.ruleStrong)
        val accent: Color = Color(T.L.accent)
        val accentWash: Color = Color(T.L.accentWash)
    }

    /** 深色（取景器、影像浏览——功能性深色，不是全局主题）。 */
    object D {
        val bg: Color = Color(T.D.bg)
        val surface: Color = Color(T.D.surface)
        val fg: Color = Color(T.D.fg)
        val fgMuted: Color = Color(T.D.fgMuted)
        val rule: Color = Color(T.D.rule)
    }

    /** 状态点颜色。只用于小圆点与小字号文本，不做色块。 */
    object S {
        val waiting: Color = Color(T.S.waiting)
        val moving: Color = Color(T.S.moving)
        val arrived: Color = Color(T.S.arrived)
        val failed: Color = Color(T.S.failed)
        val waitingOnDark: Color = Color(T.S.waitingOnDark)
        val movingOnDark: Color = Color(T.S.movingOnDark)
        val arrivedOnDark: Color = Color(T.S.arrivedOnDark)
    }

    object Sp {
        val s1: Dp = T.Sp.s1.dp
        val s2: Dp = T.Sp.s2.dp
        val s3: Dp = T.Sp.s3.dp
        val s4: Dp = T.Sp.s4.dp
        val s5: Dp = T.Sp.s5.dp
        val s6: Dp = T.Sp.s6.dp
        val s8: Dp = T.Sp.s8.dp
        val s10: Dp = T.Sp.s10.dp
        val s16: Dp = T.Sp.s16.dp
        val gutter: Dp = T.Sp.gutter.dp
    }

    object Ty {
        val hero: TextUnit = T.Ty.hero.sp
        val display: TextUnit = T.Ty.display.sp
        val title: TextUnit = T.Ty.title.sp
        val heading: TextUnit = T.Ty.heading.sp
        val body: TextUnit = T.Ty.body.sp
        val small: TextUnit = T.Ty.small.sp
        val micro: TextUnit = T.Ty.micro.sp
        val nano: TextUnit = T.Ty.nano.sp
    }

    /** 最小可点触尺寸——现场单手操作，闭着眼睛也要按得到。 */
    val touchMin: Dp = T.touchMin.dp
}
