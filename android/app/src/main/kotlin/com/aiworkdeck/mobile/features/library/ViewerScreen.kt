package com.aiworkdeck.mobile.features.library

import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import coil3.compose.AsyncImage
import com.aiworkdeck.mobile.design.Fonts
import com.aiworkdeck.mobile.design.StatusDot
import com.aiworkdeck.mobile.design.Tk
import com.aiworkdeck.mobile.design.WorkdeckTheme
import com.aiworkdeck.mobile.design.tr
import com.aiworkdeck.mobile.model.CaptureItem
import com.aiworkdeck.mobile.model.MediaKind
import java.io.File

/**
 * 全屏看大图。左右滑同一天的其他件；照片可缩放，录像/录音交给播放器。
 * 顶部只放核对要用的东西：状态、时刻、哈希前缀。不做编辑、不做分享——取证件不该从这里流出去。
 * 镜像 iOS `ViewerView`。
 */
@Composable
fun ViewerScreen(items: List<CaptureItem>, start: Int, onClose: () -> Unit) {
    if (items.isEmpty()) return
    val pager = rememberPagerState(initialPage = start.coerceIn(0, items.size - 1)) { items.size }

    WorkdeckTheme(dark = true) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
                val item = items[page]
                when (item.kind) {
                    MediaKind.photo -> ZoomablePhoto(item.localFile)
                    // 一次只起一个播放器：几段 1080p 同时解码会把中低端机的解码器占满
                    else -> PlayerPage(item.localFile, active = pager.currentPage == page)
                }
            }
            TopBar(items[pager.currentPage.coerceIn(0, items.size - 1)], pager.currentPage + 1, items.size, onClose)
        }
    }
}

@Composable
private fun TopBar(item: CaptureItem, index: Int, total: Int, onClose: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.55f)).safeDrawingPadding()
            .padding(start = Tk.Sp.s2, end = Tk.Sp.s3, bottom = Tk.Sp.s2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tk.Sp.s2),
    ) {
        Box(
            Modifier.size(Tk.touchMin).clickable(onClick = onClose)
                .semantics { contentDescription = tr("common.close") },
            contentAlignment = Alignment.Center,
        ) { Text("✕", style = Fonts.body(), color = Color.White) }

        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tk.Sp.s1)) {
                StatusDot(item.state, onDark = true)
                // 录音没有画面，播放器是一整片黑；这里点一句它是声音
                if (item.kind == MediaKind.audio) Text("♪", style = Fonts.small(), color = Color.White.copy(alpha = 0.6f))
                Text(item.state.caption, style = Fonts.small(), color = Color.White)
                Text(LibraryTime.precise(item.capturedAt), style = Fonts.mono(Tk.Ty.micro), color = Color.White.copy(alpha = 0.6f))
            }
            Text(
                item.manifest.sha256.take(12), style = Fonts.mono(Tk.Ty.nano),
                color = Color.White.copy(alpha = 0.5f),
            )
        }
        Text("$index / $total", style = Fonts.mono(Tk.Ty.micro), color = Color.White.copy(alpha = 0.6f))
    }
}

/**
 * 照片页：双指缩放、双击 1x / 2.5x 切换、放大后可拖。
 * 单指拖只在放大后才接管（`canPan`），否则会把翻页手势抢走。
 */
@Composable
private fun ZoomablePhoto(file: File) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    val state = rememberTransformableState { _, zoomChange, panChange, _ ->
        scale = (scale * zoomChange).coerceIn(1f, 5f)
        offset = if (scale > 1f) offset + panChange else Offset.Zero
    }
    AsyncImage(
        model = file,
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = Modifier.fillMaxSize()
            .graphicsLayer {
                scaleX = scale; scaleY = scale
                translationX = offset.x; translationY = offset.y
            }
            .transformable(state = state, canPan = { scale > 1f })
            .pointerInput(Unit) {
                detectTapGestures(onDoubleTap = {
                    if (scale > 1f) { scale = 1f; offset = Offset.Zero } else scale = 2.5f
                })
            },
    )
}

/**
 * 录像与录音都交给 Media3 的播放器：录音没有画面，播放器本身就是界面。
 * 播放器只在这一页可见时才建，离开立刻 [ExoPlayer.release]——不放会一直占着解码器与音频焦点。
 *
 * 不在这一层往播放器上叠任何 Compose 内容：[PlayerView] 用的是 SurfaceView，它在窗口上打的
 * 是「透明洞」，画在洞里的 Compose 内容会被一起抹掉（音符标记因此挪到了顶栏）。
 */
@OptIn(UnstableApi::class)
@Composable
private fun PlayerPage(file: File, active: Boolean) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        if (active) {
            val context = LocalContext.current
            val player = remember(file) {
                ExoPlayer.Builder(context).build().apply {
                    setMediaItem(MediaItem.fromUri(file.toURI().toString()))
                    prepare()
                }
            }
            DisposableEffect(player) { onDispose { player.release() } }
            // 播放控件避开状态栏与手势条：进度条压在导航条下面就点不着了
            AndroidView(
                factory = { PlayerView(it).apply { this.player = player; setShowNextButton(false); setShowPreviousButton(false) } },
                modifier = Modifier.fillMaxSize().safeDrawingPadding(),
            )
        }
    }
}
