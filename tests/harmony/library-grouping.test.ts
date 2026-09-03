process.env.TZ = 'Asia/Shanghai'

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { CaptureItem, MediaKind } from '../../harmony/entry/src/main/ets/model/Capture.ets'
import type { CaptureManifest, RelayProject } from '../../harmony/entry/src/main/ets/model/Capture.ets'
import { TransferState } from '../../harmony/entry/src/main/ets/model/TransferState.ets'
import { groupByDay, deleteWarningLevel, deleteWarning, projectsIn, itemsIn, UNKNOWN_PROJECT } from '../../harmony/entry/src/main/ets/model/LibraryGrouping.ets'
import { formatIso } from '../../harmony/entry/src/main/ets/model/IsoTime.ets'

let seq = 0
function item(atMs: number, state: TransferState = TransferState.arrived, project: RelayProject | null = null): CaptureItem {
  const id = `item-${seq++}`
  const manifest: CaptureManifest = {
    clientMediaId: id, sha256: 'a'.repeat(64), capturedAt: formatIso(atMs),
    deviceModel: 'x', osVersion: 'x', appVersion: 'x', fromCamera: true,
  }
  return new CaptureItem(id, MediaKind.photo, state, manifest, `/tmp/${id}.jpg`, 0, null, false, project)
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

const proj = (deviceId: string, key: string, name: string): RelayProject => ({ deviceId, key, name })

test('项目菜单：当前项目第一，其余按名称排', () => {
  const now = local(2026, 9, 2, 8, 0)
  const a = proj('d1', 'k1', '案 B')
  const b = proj('d1', 'k2', '案 A')
  const cur = proj('d1', 'k0', '案 Z')
  const items = [item(now, TransferState.arrived, a), item(now, TransferState.arrived, b), item(now, TransferState.arrived, cur)]

  // 当前项目排在最前，其余按名称升序（按码点比，与安卓 sortedBy 同口径）
  assert.deepEqual(projectsIn(items, cur), [
    { id: 'd1:k0', name: '案 Z' },
    { id: 'd1:k2', name: '案 A' },
    { id: 'd1:k1', name: '案 B' },
  ])
})

test('没记项目的件归未知项目，当前项目为空时也列出来', () => {
  const now = local(2026, 9, 2, 8, 0)
  const a = proj('d1', 'k1', '案 A')
  const items = [item(now, TransferState.arrived, null), item(now, TransferState.arrived, a)]

  // 「未知项目」不特殊照顾，和别的项目一起按名称排（码点上「未」在「案」前）
  assert.deepEqual(projectsIn(items, null), [
    { id: UNKNOWN_PROJECT, name: '未知项目' },
    { id: 'd1:k1', name: '案 A' },
  ])
})

test('当前项目即使一件都没有也排第一', () => {
  const cur = proj('d1', 'k0', '案 Z')
  assert.deepEqual(projectsIn([], cur), [{ id: 'd1:k0', name: '案 Z' }])
})

test('itemsIn 按项目标识过滤，未知项目取没记项目的件', () => {
  const now = local(2026, 9, 2, 8, 0)
  const a = proj('d1', 'k1', '案 A')
  const withProject = item(now, TransferState.arrived, a)
  const orphan = item(now, TransferState.arrived, null)
  const items = [withProject, orphan]

  assert.deepEqual(itemsIn(items, 'd1:k1').map((i) => i.id), [withProject.id])
  assert.deepEqual(itemsIn(items, UNKNOWN_PROJECT).map((i) => i.id), [orphan.id])
  assert.deepEqual(itemsIn(items, 'd1:zzz'), [])
})
