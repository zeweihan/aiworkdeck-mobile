import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { tallyOf, tallyTotal, deleteWarningLevel, type QueueState } from '../miniprogram/utils/phase.ts'
import { next, recover, applyStatus } from '../miniprogram/utils/transition.ts'
import { t } from '../miniprogram/utils/i18n.ts'

const fx = (n: string) => JSON.parse(readFileSync(join(import.meta.dirname, '..', 'contract', 'fixtures', `${n}.json`), 'utf8'))

test('fixture: tally', () => {
  for (const k of fx('tally').cases) {
    const got = tallyOf(k.states.map((s: QueueState) => ({ state: s })))
    assert.deepEqual({ ...got, total: tallyTotal(got) }, k.expect, k.name)
  }
})

test('fixture: transitions', () => {
  for (const k of fx('transitions').cases) {
    assert.equal(next(k.from, k.event, k.attempts), k.to, `${k.from}+${k.event}(${k.attempts})`)
  }
})

test('fixture: restore', () => {
  for (const k of fx('restore').cases) assert.equal(recover(k.state, k.attempts), k.expect, `${k.state}(${k.attempts})`)
})

test('fixture: status-merge', () => {
  for (const k of fx('status-merge').cases) assert.deepEqual(applyStatus(k.state, k.status), k.expect, k.name)
})

test('fixture: delete-warning', () => {
  for (const k of fx('delete-warning').cases) assert.deepEqual(deleteWarningLevel(k.states), k.expect, JSON.stringify(k.states))
})

test('i18n: 占位符替换与缺键行为', () => {
  assert.equal(t('delete.title', { n: 3 }), '删除 3 件')
  assert.equal(t('tally.failedSuffix', { m: 2 }), '含 2 失败')
  assert.equal(t('no.such.key'), 'no.such.key')
})
