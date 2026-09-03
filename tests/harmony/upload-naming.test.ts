process.env.TZ = 'Asia/Shanghai'

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { MediaKind } from '../../harmony/entry/src/main/ets/model/Capture.ets'
import { uploadFileName } from '../../harmony/entry/src/main/ets/model/UploadNaming.ets'

const at = Date.UTC(2026, 8, 2, 1, 5, 7)   // 上海 2026-09-02 09:05:07
const id = 'abcd1234-5678-90ef-ghij-klmnopqrstuv'

test('照片走影像前缀与 jpg', () => {
  assert.equal(uploadFileName(MediaKind.photo, at, id), '现场影像-20260902-090507-abcd.jpg')
})

test('录像走影像前缀与 mp4', () => {
  assert.equal(uploadFileName(MediaKind.video, at, id), '现场影像-20260902-090507-abcd.mp4')
})

test('录音走录音前缀与 m4a', () => {
  assert.equal(uploadFileName(MediaKind.audio, at, id), '现场录音-20260902-090507-abcd.m4a')
})

test('只取 clientMediaId 前 4 位', () => {
  assert.equal(uploadFileName(MediaKind.photo, at, '0f3a9c77-dead-beef'), '现场影像-20260902-090507-0f3a.jpg')
})

test('时间戳补零', () => {
  assert.equal(uploadFileName(MediaKind.photo, Date.UTC(2026, 0, 5, 15, 2, 3), id), '现场影像-20260105-230203-abcd.jpg')
})
