package com.aiworkdeck.mobile.features.home

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material3.Text
import com.aiworkdeck.mobile.design.Fonts
import com.aiworkdeck.mobile.design.Tk
import com.aiworkdeck.mobile.services.Loc
import java.time.Instant

/**
 * 淡水印：时间到秒、项目名、坐标与精度。
 *
 * **只叠加在取景与展示层，不烧录进照片字节**：照片是 JPEG 直出保 SHA-256「原始采集」，
 * 烧录会毁掉证据链（决策 D3，与 iOS 同）。
 */
@Composable
fun Watermark(now: Instant, projectName: String, loc: Loc?, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(WatermarkFormat.time(now), style = Fonts.mono(Tk.Ty.small), color = Color.White.copy(alpha = 0.78f))
        Text(
            projectName, style = Fonts.micro(), color = Color.White.copy(alpha = 0.6f),
            maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
        Text(WatermarkFormat.coord(loc), style = Fonts.mono(Tk.Ty.nano), color = Color.White.copy(alpha = 0.6f))
    }
}
