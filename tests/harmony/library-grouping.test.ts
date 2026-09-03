process.env.TZ = 'Asia/Shanghai'

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { CaptureItem, MediaKind } from '../../harmony/entry/src/main/ets/model/Capture.ets'
import type { CaptureManifest } from '../../harmony/entry/src/main/ets/model/Capture.ets'
import { TransferState } from '../../harmony/entry/src/main/ets/model/TransferState.ets'
import { groupByDay, deleteWarningLevel, deleteWarning } from '../../harmony/entry/src/main/ets/model/LibraryGrouping.ets'
import { formatIso } from '../../harmony/entry/src/main/ets/model/IsoTime.ets'

let seq = 0
function item(atMs: number, state: TransferState = TransferState.arrived): CaptureItem {
  const id = `item-${seq++}`
  const manifest: CaptureManifest = {
    clientMediaId: id, sha256: 'a'.repeat(64), capturedAt: formatIso(atMs),
    deviceModel: 'x', osVersion: 'x', appVersion: 'x', fromCamera: true,
  }
  return new CaptureItem(id, MediaKind.photo, state, manifest, `/tmp/${id}.jpg`, 0, null, false, null)
}

const local = (y: number, m: number, d: number, hh: number, mm: number) => new Date(y, m - 1, d, hh, mm, 0).getTime()

test('按本地自然日分段，新的在前，段头带件数', () => {
  const day1a = item(local(2026, 9, 2, 8, 0))
  const day1b = item(local(2026, 9, 2, 9, 0))
  const day0 = item(local(2026, 9, 1, 10, 0))

  const sections = groupByDay([day0, day1a, day1b])

  assert.equal(sections.length, 2)
  assert.equal(sections[0].title, '9月2日 · 2 件')
  assert.equal(sections[1].title, '9月1日 · 1 件')
  assert.equal(sections[0].key, '2026-09-02')
  assert.equal(sections[1].key, '2026-09-01')
  // 段内按时间倒序：09:00 在 08:00 前面
  assert.deepEqual(sections[0].items.map((i) => i.id), [day1b.id, day1a.id])
  assert.deepEqual(sections[1].items.map((i) => i.id), [day0.id])
})

test('跨年也按日分开', () => {
  const a = item(local(2026, 1, 1, 0, 30))
  const b = item(local(2025, 12, 31, 23, 30))
  const sections = groupByDay([b, a])
  assert.deepEqual(sections.map((s) => s.key), ['2026-01-01', '2025-12-31'])
  assert.equal(sections[0].title, '1月1日 · 1 件')
})

test('空列表没有段', () => {
  assert.deepEqual(groupByDay([]), [])
})

test('删除等级取最坏的桶', () => {
  assert.deepEqual(deleteWarningLevel([TransferState.arrived, TransferState.uploaded, TransferState.waiting]), { level: 'unsent', n: 1 })
  assert.deepEqual(deleteWarningLevel([TransferState.arrived, TransferState.uploaded]), { level: 'staged', n: 1 })
  assert.deepEqual(deleteWarningLevel([TransferState.arrived, TransferState.arrived]), { level: 'landed', n: 2 })
  assert.deepEqual(deleteWarningLevel([]), { level: 'landed', n: 0 })
})

test('删除警告文案按等级取键并带件数', () => {
  assert.equal(deleteWarning([TransferState.arrived, TransferState.arrived]), '删除 2 件本地原图？电脑上已有副本。')
  assert.equal(deleteWarning([TransferState.waiting, TransferState.failed, TransferState.arrived]),
    '其中 2 件还没送出去。删了就没了，无法找回。')
})
