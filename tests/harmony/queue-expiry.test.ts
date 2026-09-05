import { test } from 'node:test'
import assert from 'node:assert/strict'
import { EXPIRY_WARN_DAYS, expiryDaysLeft } from '../../harmony/entry/src/main/ets/model/QueueExpiry.ets'

const NOW = Date.parse('2026-09-03T00:00:00Z')

test('剩余天数向上取整，与安卓 QueueExpiry.kt 同口径', () => {
  assert.equal(expiryDaysLeft('2026-09-05T18:00:00Z', NOW), 3)
  assert.equal(expiryDaysLeft('2026-09-03T01:00:00Z', NOW), 1)
})

test('已过期算 0，不给负数', () => {
  assert.equal(expiryDaysLeft('2026-09-02T23:00:00Z', NOW), 0)
  assert.equal(expiryDaysLeft('2026-09-03T00:00:00Z', NOW), 0)
})

test('没有到期时刻或解不出来就不提醒，宁可不说也不凭空造日期', () => {
  assert.equal(expiryDaysLeft(null, NOW), null)
  assert.equal(expiryDaysLeft('不是时间', NOW), null)
  assert.equal(expiryDaysLeft('', NOW), null)
})

test('带偏移的时刻按绝对时刻算，不受本机时区影响', () => {
  // 2026-09-06T02:00:00+08:00 === 2026-09-05T18:00:00Z
  assert.equal(expiryDaysLeft('2026-09-06T02:00:00+08:00', NOW), 3)
})

test('提醒阈值三天，与安卓 EXPIRY_WARN_DAYS 一致', () => {
  assert.equal(EXPIRY_WARN_DAYS, 3)
})
