package com.aiworkdeck.mobile.features.home

import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.viewinterop.AndroidView

/**
 * 取景画面。[PreviewView] 由调用方持有（相机会话要绑同一个视图，重组不能换实例），
 * 这里只负责把它挂进 Compose 树。
 *
 * FILL_CENTER：取景框铺满、超出部分裁掉，与 iOS 的 `.resizeAspectFill` 一致——
 * 现场取景要「所见即所得」的画幅感，留黑边会让人误判取景范围。
 *
 * 两处不能省：
 * - COMPATIBLE（TextureView）而不是默认的 SurfaceView。SurfaceView 是独立的合成层，Compose
 *   裁不动它；取景本来就要和水印、计数行叠在一起，画对了比省那点合成开销重要。
 * - [clipToBounds]。FILL_CENTER 是「把画面放大到铺满、超出的裁掉」，实现上内部的画面视图
 *   比 PreviewView 本身大一圈，不裁就会溢出到顶部计数行上（实测盖掉半行）。
 */
@Composable
fun CameraPreview(view: PreviewView, modifier: Modifier = Modifier) {
    AndroidView(
        factory = {
            view.apply {
                scaleType = PreviewView.ScaleType.FILL_CENTER
                implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            }
        },
        modifier = modifier.clipToBounds(),
    )
}
