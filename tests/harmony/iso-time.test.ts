process.env.TZ = 'Asia/Shanghai'   // 本地时区在断言里是硬事实，固定住

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { formatIso, parseIso } from '../../harmony/entry/src/main/ets/model/IsoTime.ets'

const utc = Date.UTC(2026, 8, 2, 9, 0, 0)   // 2026-09-02T09:00:00Z = 上海 17:00

test('formatIso 写本地时刻带本地偏移', () => {
  assert.equal(formatIso(utc), '2026-09-02T17:00:00+08:00')
})

test('formatIso 手拼的偏移带分钟位', () => {
  const saved = process.env.TZ
  try {
    process.env.TZ = 'Asia/Kolkata'   // +05:30
    assert.equal(formatIso(utc), '2026-09-02T14:30:00+05:30')
  } finally {
    process.env.TZ = saved
  }
})

test('parseIso 认带偏移的', () => {
  assert.equal(parseIso('2026-09-02T17:00:00+08:00'), utc)
  assert.equal(parseIso('2026-09-02T05:00:00-04:00'), utc)
  assert.equal(parseIso('2026-09-02T05:00:00-0400'), utc)   // 偏移不带冒号
})

test('parseIso 认 Z 与小数秒', () => {
  assert.equal(parseIso('2026-09-02T09:00:00Z'), utc)
  assert.equal(parseIso('2026-09-02T09:00:00.123Z'), utc + 123)
})

test('parseIso 无偏移时按本地时区补齐', () => {
  assert.equal(parseIso('2026-09-02T17:00:00'), utc)
  assert.equal(parseIso('2026-09-09T10:00:00'), Date.UTC(2026, 8, 9, 2, 0, 0))
})

test('parseIso 认没有秒的形式', () => {
  assert.equal(parseIso('2026-09-02T17:00'), utc)
})

test('parseIso 解不出来给 null', () => {
  assert.equal(parseIso(''), null)
  assert.equal(parseIso('not a time'), null)
  assert.equal(parseIso('2026-13-02T17:00:00'), null)
})

test('format 与 parse 往返', () => {
  assert.equal(parseIso(formatIso(utc)), utc)
})
