import { test } from 'node:test'
import assert from 'node:assert/strict'
import { RecordingClock } from '../../harmony/entry/src/main/ets/model/RecordingClock.ets'

const t0 = 1_000_000_000
const at = (s: number) => t0 + s * 1000

test('未开始时零秒', () => {
  const c = new RecordingClock()
  assert.equal(c.elapsed(at(100)), 0)
  assert.equal(c.paused, false)
  assert.equal(c.resumedAt, null)
})

test('运行中从开录时刻起算', () => {
  const c = new RecordingClock()
  c.start(t0)
  assert.equal(c.elapsed(at(12)), 12)
  assert.equal(c.elapsedBase, 0)
  assert.equal(c.resumedAt, t0)
  assert.equal(c.paused, false)
})

test('中断冻结秒数', () => {
  const c = new RecordingClock()
  c.start(t0)
  c.interrupt(at(30))
  assert.equal(c.paused, true)
  assert.equal(c.resumedAt, null)
  assert.equal(c.elapsedBase, 30)
  assert.equal(c.elapsed(at(90)), 30)
})

test('续录从已累计处接着走', () => {
  const c = new RecordingClock()
  c.start(t0)
  c.interrupt(at(30))
  c.resume(at(90))
  assert.equal(c.paused, false)
  assert.equal(c.resumedAt, at(90))
  assert.equal(c.elapsedBase, 30)
  assert.equal(c.elapsed(at(100)), 40)
})

test('多次中断累计', () => {
  const c = new RecordingClock()
  c.start(t0)
  c.interrupt(at(10)); c.resume(at(20))
  c.interrupt(at(25)); c.resume(at(60))
  c.interrupt(at(70))
  assert.equal(c.elapsedBase, 25)   // 10 + 5 + 10
  c.resume(at(100))
  assert.equal(c.elapsed(at(103)), 28)
})

test('重复中断幂等：第二次不再扣一段', () => {
  const c = new RecordingClock()
  c.start(t0)
  c.interrupt(at(10))
  c.interrupt(at(50))
  assert.equal(c.elapsedBase, 10)
  assert.equal(c.elapsed(at(80)), 10)
})

test('没中断时 resume 是空操作', () => {
  const c = new RecordingClock()
  c.start(t0)
  c.resume(at(50))
  assert.equal(c.resumedAt, t0)
  assert.equal(c.elapsed(at(60)), 60)
})

test('没开录时 interrupt 是空操作', () => {
  const c = new RecordingClock()
  c.interrupt(at(5))
  assert.equal(c.paused, false)
  assert.equal(c.elapsed(at(9)), 0)
})

test('重新开录清掉上一轮', () => {
  const c = new RecordingClock()
  c.start(t0)
  c.interrupt(at(10))
  c.start(at(100))
  assert.equal(c.elapsedBase, 0)
  assert.equal(c.paused, false)
  assert.equal(c.elapsed(at(105)), 5)
})
