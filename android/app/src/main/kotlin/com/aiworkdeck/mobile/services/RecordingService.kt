package com.aiworkdeck.mobile.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.aiworkdeck.mobile.MainActivity
import com.aiworkdeck.mobile.design.tr
import com.aiworkdeck.mobile.model.MediaKind
import com.aiworkdeck.mobile.model.RelayProject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.util.logging.Logger

/**
 * 录音前台服务（dev-board#405）：录音切后台、锁屏都继续，常驻通知里有计时与「停止录音」。
 *
 * 界面只负责发起与停止（[start] / [stop]），MediaRecorder 由服务持有；开录参数（项目、位置快照）
 * 经 [RecordingState.request] 传入。停止时服务**自己落库**——用户很可能是从通知栏按的停，
 * 此时 Activity 未必活着，不能指望界面来收这一段。
 *
 * 位置取**开录时**的快照：取证语义上开录地点更对，服务也拿不到界面里的定位。
 */
class RecordingService : Service() {
    private val logger = Logger.getLogger("RecordingService")
    private var engine: AudioRecorderService? = null
    private var request: RecordingState.StartRequest? = null
    private var startedAt: Long = 0L
    private var destroyed = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopAndStore()
            return START_NOT_STICKY
        }
        if (engine != null) return START_NOT_STICKY
        val req = RecordingState.takeRequest()
        val now = System.currentTimeMillis()
        // 先举通知再开录：startForegroundService 起来的服务 5 秒内不 startForeground 会被系统掐掉。
        // 举不起来（API 34+ 没有麦克风权限会抛 SecurityException）就直接退出，状态保持未录。
        try {
            ensureChannel(this)
            ServiceCompat.startForeground(
                this, NOTIFICATION_ID, notification(now), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } catch (e: Exception) {
            logger.warning("录音前台服务举通知失败: ${e.message}")
            RecordingState.finish()
            stopSelf()
            return START_NOT_STICKY
        }
        val eng = AudioRecorderService(this)
        if (!eng.start()) {
            RecordingState.finish()
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        engine = eng
        request = req
        startedAt = eng.recordingStartedAt ?: now
        RecordingState.begin(startedAt)
        return START_NOT_STICKY
    }

    /**
     * 停录并落库。停表的那一刻就把界面状态翻回去；写盘在进程级作用域里做，服务被销毁也不中断。
     * 顺序与 `AppModel.store` 一致：先进库、再排上传、最后踢一脚队列；录音不存相册，服务里不用管。
     */
    private fun stopAndStore() {
        val eng = engine
        engine = null
        val req = request
        val at = startedAt
        RecordingState.finish()
        val file = eng?.stop()
        if (file == null) {
            finishService()
            return
        }
        val app = applicationContext
        storeScope.launch {
            try {
                val item = ServiceLocator.store.save(MediaKind.audio, file, Instant.ofEpochMilli(at), req?.loc, req?.project)
                UploadWorker.enqueue(app)
                RecordingState.stored.emit(item)
            } catch (e: Exception) {
                logger.warning("录音落库失败: ${e.message}")
            } finally {
                withContext(Dispatchers.Main) { finishService() }
            }
            ServiceLocator.queueOrNull()?.kick()
        }
    }

    private fun finishService() {
        if (destroyed) return
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** 系统杀服务的兜底：还在录就停下来落库，已录的内容不能丢。 */
    override fun onDestroy() {
        if (engine != null) stopAndStore()
        destroyed = true
        super.onDestroy()
    }

    private fun notification(startedAt: Long): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, RecordingService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(tr("home.recording.audio"))
            .setContentText(tr("home.audio.backgroundOk"))
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setUsesChronometer(true)
            .setWhen(startedAt)
            .setShowWhen(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(open)
            .addAction(0, tr("home.shutter.stopAudio"), stop)
        // Android 16 起可申请提升为 Live Updates（状态栏常驻小胶囊）
        if (Build.VERSION.SDK_INT >= 36) builder.setRequestPromotedOngoing(true)
        return builder.build()
    }

    companion object {
        private const val CHANNEL_ID = "recording"
        private const val NOTIFICATION_ID = 2
        private const val ACTION_STOP = "com.aiworkdeck.mobile.action.STOP_RECORDING"

        /** 落库作用域是进程级的：服务被销毁时正在写盘的那一件也要写完。 */
        private val storeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        /** 开录。必须在应用前台调用（API 34+ 麦克风类前台服务不许后台启动）。 */
        fun start(context: Context, project: RelayProject?, loc: Loc?) {
            RecordingState.request = RecordingState.StartRequest(project, loc)
            ContextCompat.startForegroundService(context, Intent(context, RecordingService::class.java))
        }

        /** 停录。服务已在前台，普通 startService 就够；万一应用已退到后台被拒，再走前台服务通道。 */
        fun stop(context: Context) {
            val intent = Intent(context, RecordingService::class.java).setAction(ACTION_STOP)
            runCatching { context.startService(intent) }
                .onFailure { ContextCompat.startForegroundService(context, intent) }
        }

        /** 幂等：渠道已存在就什么也不做。默认重要度但无声音——录音中不该被自己的通知打断。 */
        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                CHANNEL_ID, tr("notify.channel.recording"), NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { setSound(null, null) }
            manager.createNotificationChannel(channel)
        }
    }
}
