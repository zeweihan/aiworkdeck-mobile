process.env.TZ = 'Asia/Shanghai'

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { gpsChip, watermarkCoord, watermarkLines, watermarkTime } from '../../harmony/entry/src/main/ets/model/Watermark.ets'
import type { Loc } from '../../harmony/entry/src/main/ets/model/Loc.ets'

const loc = (lat: number, lon: number, accuracy: number | null): Loc => ({ lat, lon, accuracy })

// 与安卓 WatermarkFormatTest.kt 逐条对拍：秒级时间与坐标精度是取证信息，
// 格式错了不该等到人肉走查才发现。

test('时间到秒，按本机时区', () => {
  const at = Date.UTC(2026, 8, 2, 9, 5, 7)   // 上海 2026-09-02 17:05:07
  assert.equal(watermarkTime(at), '2026-09-02 17:05:07')
})

test('坐标五位小数，精度四舍五入到整米', () => {
  assert.equal(watermarkCoord(loc(31.230581, 121.473702, 12.4)), '31.23058, 121.47370 · ±12 米')
})

test('没有精度就只写坐标', () => {
  assert.equal(watermarkCoord(loc(31.230581, 121.473702, null)), '31.23058, 121.47370')
})

test('没有定位说「定位中」，不写零零坐标', () => {
  assert.equal(watermarkCoord(null), '定位中')
  assert.equal(gpsChip(null), '定位中')
  assert.equal(gpsChip(loc(31.0, 121.0, null)), '定位中')
})

test('顶栏芯片只给精度', () => {
  assert.equal(gpsChip(loc(31.230581, 121.473702, 8.6)), '±9 米')
})

test('三行：时间、项目名、坐标', () => {
  const at = Date.UTC(2026, 8, 2, 9, 5, 7)
  assert.deepEqual(watermarkLines(at, '某小区渗漏', loc(31.230581, 121.473702, 12.4)),
    ['2026-09-02 17:05:07', '某小区渗漏', '31.23058, 121.47370 · ±12 米'])
})

test('没有项目名就不留空行', () => {
  const at = Date.UTC(2026, 8, 2, 9, 5, 7)
  assert.deepEqual(watermarkLines(at, null, null), ['2026-09-02 17:05:07', '定位中'])
})
