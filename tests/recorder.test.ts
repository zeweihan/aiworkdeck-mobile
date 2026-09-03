import { test } from 'node:test'
import assert from 'node:assert/strict'
import { startRecording, stopRecording, resumeIfInterrupted } from '../miniprogram/utils/recorder.ts'

/**
 * 假 RecorderManager：把 on* 回调存起来，测试里手动触发；
 * start/stop/resume 只计数（微信通话打断 → 中断结束自动 resume 续录同一段）。
 */
function fakeManager() {
  const handlers: Record<string, (res?: unknown) => void> = {}
  const calls = { start: 0, stop: 0, resume: 0 }
  const on = (name: string) => (cb: (res?: unknown) => void) => { handlers[name] = cb }
  return {
    handlers,
    calls,
    start: () => { calls.start += 1 },
    stop: () => { calls.stop += 1 },
    resume: () => { calls.resume += 1 },
    pause: () => {},
    onStart: on('start'),
    onStop: on('stop'),
    onError: on('error'),
    onPause: on('pause'),
    onResume: on('resume'),
    onInterruptionBegin: on('interruptionBegin'),
    onInterruptionEnd: on('interruptionEnd'),
    onFrameRecorded: on('frameRecorded'),
  }
}

const mgr = fakeManager()
// recorder.ts 只在 getManager / ensureRecordAuth 里碰 wx，模块加载不触 wx，这里先装再录
;(globalThis as unknown as { wx: unknown }).wx = {
  getRecorderManager: () => mgr,
  authorize: (o: { success?: () => void }) => o.success?.(),
  setStorageSync: () => {},
  getStorageSync: () => undefined,
}

const project = { deviceId: 'd', projectKey: '1', name: 'p' } as never

test('中断开始回调 true；中断结束自动 resume；onResume 回调 false', async () => {
  const seen: boolean[] = []
  const started = await startRecording(project, {
    onSegment: () => {},
    onFinish: () => {},
    onError: () => {},
    onInterrupted: (v) => seen.push(v),
  })
  assert.equal(started, true)
  assert.equal(mgr.calls.start, 1)

  mgr.handlers.interruptionBegin()
  assert.deepEqual(seen, [true])

  mgr.handlers.interruptionEnd()
  assert.equal(mgr.calls.resume, 1)

  mgr.handlers.resume()
  assert.deepEqual(seen, [true, false])

  // 已续录：onShow 兜底不再重复 resume
  resumeIfInterrupted()
  assert.equal(mgr.calls.resume, 1)

  // 中断中 onShow 兜底会补一次 resume
  mgr.handlers.interruptionBegin()
  resumeIfInterrupted()
  assert.equal(mgr.calls.resume, 2)

  // 手动停止：末段 onStop 后会话结束，onInterrupted 不再触发
  stopRecording()
  assert.equal(mgr.calls.stop, 1)
  mgr.handlers.stop({ tempFilePath: '' })
  resumeIfInterrupted()
  assert.equal(mgr.calls.resume, 2)
})

test('没有会话时 resumeIfInterrupted 是空操作', () => {
  const before = mgr.calls.resume
  resumeIfInterrupted()
  assert.equal(mgr.calls.resume, before)
})
