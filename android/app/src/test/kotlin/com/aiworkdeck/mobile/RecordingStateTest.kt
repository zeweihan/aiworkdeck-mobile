package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.RelayProject
import com.aiworkdeck.mobile.model.TransferState
import com.aiworkdeck.mobile.services.Loc
import com.aiworkdeck.mobile.services.RecordingState
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

class RecordingStateTest {
    // 进程级单例：每个用例结束都要归零，否则用例之间会互相看见对方的状态
    @After fun reset() {
        RecordingState.finish()
        RecordingState.takeRequest()
    }

    @Test fun idleByDefault() {
        assertFalse(RecordingState.isRecording)
        assertNull(RecordingState.startedAt)
        assertNull(RecordingState.takeRequest())
    }

    @Test fun beginMarksRecordingWithStartedAt() {
        RecordingState.begin(1_700_000_000_000L)
        assertTrue(RecordingState.isRecording)
        assertEquals(1_700_000_000_000L, RecordingState.startedAt)
    }

    @Test fun finishClearsRecordingAndStartedAt() {
        RecordingState.begin(42L)
        RecordingState.finish()
        assertFalse(RecordingState.isRecording)
        assertNull(RecordingState.startedAt)
    }

    @Test fun takeRequestHandsOverOnceThenNull() {
        val project = RelayProject(deviceId = "dev-1", deviceName = null, key = "p", name = "现场")
        val loc = Loc(lat = 31.2, lon = 121.5, accuracy = 8.0)
        RecordingState.request = RecordingState.StartRequest(project, loc)

        val taken = RecordingState.takeRequest()
        assertEquals(RecordingState.StartRequest(project, loc), taken)
        // 服务启动时取走一次就清空：再来一次 onStartCommand 不能拿着旧参数重复开录
        assertNull(RecordingState.takeRequest())
    }

    @Test fun storedDeliversItemToCollector() = runTest {
        val item = TestItems.make(TransferState.waiting)
        val received = async { RecordingState.stored.first() }
        runCurrent()
        RecordingState.stored.emit(item)
        assertEquals(item, received.await())
    }
}
