import { test } from 'node:test'
import assert from 'node:assert/strict'
import { Backoff } from '../../harmony/entry/src/main/ets/model/Backoff.ets'

test('首败 60 秒后重试', () => {
  const b = new Backoff()
  assert.equal(b.seconds, 60)
  assert.equal(b.nextAt, 0)
  b.onFailure(1_000)
  assert.equal(b.nextAt, 61_000)
  assert.equal(b.seconds, 120)
})

test('逐次翻倍并在 900 秒封顶', () => {
  const b = new Backoff()
  const seen: number[] = []
  let now = 0
  for (let i = 0; i < 6; i++) { b.onFailure(now); seen.push(b.seconds); now = b.nextAt }
  assert.deepEqual(seen, [120, 240, 480, 900, 900, 900])
})

test('间隔按当次的秒数排，不用翻倍后的', () => {
  const b = new Backoff()
  b.onFailure(0)
  assert.equal(b.nextAt, 60_000)        // 第一次等 60 秒
  b.onFailure(60_000)
  assert.equal(b.nextAt, 60_000 + 120_000)  // 第二次等 120 秒
})

test('成功复位回 60 秒', () => {
  const b = new Backoff()
  b.onFailure(0); b.onFailure(0); b.onFailure(0)
  assert.equal(b.seconds, 480)
  b.reset()
  assert.equal(b.seconds, 60)
  b.onFailure(5_000)
  assert.equal(b.nextAt, 65_000)
})
