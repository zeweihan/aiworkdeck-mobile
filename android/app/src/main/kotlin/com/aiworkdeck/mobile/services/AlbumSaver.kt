package com.aiworkdeck.mobile.services

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import com.aiworkdeck.mobile.model.MediaKind
import java.io.File
import java.io.IOException
import java.util.logging.Logger

/**
 * 存进系统相册。**这是「原件只留在应用沙盒」那条默认的反转**，由 `Prefs.saveToAlbum` 开关控制，
 * 与 iOS 端同一权衡：手机丢了、相册被翻，尽调材料不该躺在相册里，所以要用户知情选择。
 *
 * 录音不进相册：`MediaStore.Audio` 会把现场录音混进音乐库，取证录音不属于那里（iOS 同）。
 *
 * 走 MediaStore 的 IS_PENDING 两段式：先占位再写字节，写完才清 pending。中途崩溃留下的是
 * 一条对相册不可见的挂起记录，不会在相册里出现一张打不开的破图。
 */
object AlbumSaver {
    private const val FOLDER = "AI WorkDeck"
    private val logger = Logger.getLogger("AlbumSaver")

    fun save(context: Context, file: File, kind: MediaKind): Boolean {
        if (kind == MediaKind.audio) return false
        val relative = when (kind) {
            MediaKind.video -> "${Environment.DIRECTORY_MOVIES}/$FOLDER"
            else -> "${Environment.DIRECTORY_PICTURES}/$FOLDER"
        }
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, if (kind == MediaKind.video) "video/mp4" else "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        // 占位这两步（getContentUri/insert）本身也会抛：外置卷没挂载、MediaStore 拒收文件名时
        // 都是 IllegalArgumentException/IllegalStateException。这是在进程级协程里跑的，
        // 漏出去就是整个进程崩掉，所以连它们一起包进 try。
        //
        // 占好位之后每一条失败路径都必须落到下面那个 catch 里：中途 return 会把这条
        // IS_PENDING=1 的空记录永远留在相册库里（对用户不可见，删也删不着）。
        // 所以拿不到输出流是抛异常而不是 return false。
        var uri: Uri? = null
        return try {
            val collection = when (kind) {
                MediaKind.video -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val target = resolver.insert(collection, values) ?: return false
            uri = target
            val sink = resolver.openOutputStream(target) ?: throw IOException("openOutputStream 返回 null: $target")
            sink.use { out -> file.inputStream().use { it.copyTo(out) } }
            resolver.update(target, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            true
        } catch (e: Exception) {
            // 相册失败不影响取证链：库里那份原件才是唯一可信的一份，这里只记一笔
            logger.warning("存相册失败: ${e.message}")
            uri?.let { runCatching { resolver.delete(it, null, null) } }
            false
        }
    }
}
