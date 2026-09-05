import { test } from 'node:test'
import assert from 'node:assert/strict'
import { formatBytes, formatClock, formatHm, formatHms } from '../../harmony/entry/src/main/ets/model/Format.ets'

test('小于 1 KB 直接给整数字节', () => {
  assert.equal(formatBytes(0), '0 B')
  assert.equal(formatBytes(512), '512 B')
  assert.equal(formatBytes(1023), '1023 B')
})

test('1024 进位，与 iOS 的 binary 口径一致', () => {
  assert.equal(formatBytes(1024), '1.0 KB')
  assert.equal(formatBytes(1536), '1.5 KB')
  assert.equal(formatBytes(1024 * 1024), '1.0 MB')
  assert.equal(formatBytes(1024 * 1024 * 1024), '1.0 GB')
})

test('小于 10 留一位小数，10 以上取整', () => {
  assert.equal(formatBytes(Math.round(4.73 * 1024 * 1024 * 1024)), '4.7 GB')
  assert.equal(formatBytes(10 * 1024 * 1024 * 1024), '10 GB')
  assert.equal(formatBytes(20 * 1024 * 1024 * 1024), '20 GB')
})

test('封顶在 TB，负数按 0 算', () => {
  assert.equal(formatBytes(3 * 1024 ** 4), '3.0 TB')
  assert.equal(formatBytes(2048 * 1024 ** 4), '2048 TB')
  assert.equal(formatBytes(-1), '0 B')
})

test('录制计时 mm:ss，与安卓 WatermarkFormat.duration 同口径', () => {
  assert.equal(formatClock(0), '00:00')
  assert.equal(formatClock(9), '00:09')
  assert.equal(formatClock(59), '00:59')
  assert.equal(formatClock(60), '01:00')
  assert.equal(formatClock(605), '10:05')
})

test('超过一小时继续加分钟，不进位到小时', () => {
  assert.equal(formatClock(3600), '60:00')
  assert.equal(formatClock(3661), '61:01')
})

test('秒数向下取整，负数按 0 算', () => {
  assert.equal(formatClock(12.9), '00:12')
  assert.equal(formatClock(-5), '00:00')
})

test('图集时刻 HH:mm，格子上只到分', () => {
  assert.equal(formatHm(new Date(2026, 8, 3, 9, 5, 7).getTime()), '09:05')
  assert.equal(formatHm(new Date(2026, 8, 3, 23, 59, 59).getTime()), '23:59')
  assert.equal(formatHm(new Date(2026, 8, 3, 0, 0, 0).getTime()), '00:00')
})

test('查看器时刻 HH:mm:ss，核对取证件要到那一下', () => {
  assert.equal(formatHms(new Date(2026, 8, 3, 9, 5, 7).getTime()), '09:05:07')
  assert.equal(formatHms(new Date(2026, 8, 3, 23, 59, 59).getTime()), '23:59:59')
  assert.equal(formatHms(new Date(2026, 8, 3, 0, 0, 0).getTime()), '00:00:00')
})
