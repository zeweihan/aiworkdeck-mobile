package com.aiworkdeck.mobile.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import java.io.File
import java.util.UUID

/**
 * 现场录音。参数与 iOS `AudioRecorderService` 对齐：AAC / MPEG-4 容器（.m4a）、44.1kHz、
 * 单声道、64kbps——人声清晰，一小时约 28MB，走与照片同一条 EvidenceStore → UploadQueue 链路。
 *
 * 录音不经过相机会话：麦克风不需要点亮摄像头，也不该占着取景。
 */
class AudioRecorderService(private val context: Context) {
    var isRecording by mutableStateOf(false)
        private set

    /** 录制开始的墙钟时刻。落库用的采集时刻也取它——「什么时候开始录」比「什么时候按停」重要。 */
    var recordingStartedAt by mutableStateOf<Long?>(null)
        private set

    private var recorder: MediaRecorder? = null
    private var file: File? = null

    /** 开录。没有麦克风权限直接返回 false，由界面去解释，不在这里弹东西。 */
    fun start(): Boolean {
        if (recorder != null) return true
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return false
        val target = File(context.cacheDir, "cap-${UUID.randomUUID()}.m4a")
        @Suppress("DEPRECATION")
        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else MediaRecorder()
        return try {
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioSamplingRate(44_100)
            r.setAudioChannels(1)
            r.setAudioEncodingBitRate(64_000)
            r.setOutputFile(target.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            file = target
            isRecording = true
            recordingStartedAt = System.currentTimeMillis()
            true
        } catch (_: Exception) {
            r.release()
            target.delete()
            false
        }
    }

    /**
     * 停录并交出文件。停得太快（不足一秒）MediaRecorder 会抛，此时文件里没有可用数据，
     * 直接删掉返回 null——留一个放不出声的 0 字节件比没有更糟。
     */
    fun stop(): File? {
        val r = recorder ?: return null
        val target = file
        recorder = null
        file = null
        isRecording = false
        recordingStartedAt = null
        return try {
            r.stop()
            r.release()
            target?.takeIf { it.exists() && it.length() > 0 }
        } catch (_: Exception) {
            r.release()
            target?.delete()
            null
        }
    }
}
