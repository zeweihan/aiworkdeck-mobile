package com.aiworkdeck.mobile.design

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em

/**
 * 字重/字体不是纯数据，手写在这里；尺寸引用 [Tk.Ty]（生成自契约）。
 * 与 iOS `T.F`（`ios/Sources/Design/Typography.swift`）同名同用途。
 */
object Fonts {
    /** 只给关键数字：等宽、Light。 */
    fun hero(): TextStyle = TextStyle(fontSize = Tk.Ty.hero, fontWeight = FontWeight.Light, fontFamily = FontFamily.Monospace)
    fun display(): TextStyle = TextStyle(fontSize = Tk.Ty.display, fontWeight = FontWeight.SemiBold)
    fun title(): TextStyle = TextStyle(fontSize = Tk.Ty.title, fontWeight = FontWeight.SemiBold)
    fun heading(): TextStyle = TextStyle(fontSize = Tk.Ty.heading, fontWeight = FontWeight.SemiBold)
    fun body(): TextStyle = TextStyle(fontSize = Tk.Ty.body)
    fun small(): TextStyle = TextStyle(fontSize = Tk.Ty.small)
    fun micro(): TextStyle = TextStyle(fontSize = Tk.Ty.micro)

    /**
     * 全大写、字距拉开的小标签——这套排版的签名。字距在这里（0.14em），大写在调用方做
     * （`text.uppercase()`）：`TextStyle` 没有大小写变换，中文文案本来就没有大小写，
     * 只对英文词典生效，符合预期。
     */
    fun nano(): TextStyle = TextStyle(fontSize = Tk.Ty.nano, fontWeight = FontWeight.Medium, letterSpacing = 0.14.em)

    /** 哈希、时间、坐标、计数一律等宽——取证信息要能逐字符核对。 */
    fun mono(size: TextUnit, weight: FontWeight = FontWeight.Normal): TextStyle =
        TextStyle(fontSize = size, fontWeight = weight, fontFamily = FontFamily.Monospace)
}
