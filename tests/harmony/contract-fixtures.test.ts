import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { TransferStateOps, TransferState, TransferEvent } from '../../harmony/entry/src/main/ets/model/TransferState.ets'
import { tallyOf } from '../../harmony/entry/src/main/ets/model/TransferTally.ets'
import { deleteWarningLevel } from '../../harmony/entry/src/main/ets/model/LibraryGrouping.ets'

const fx = (n: string) => JSON.parse(readFileSync(join(import.meta.dirname, '..', '..', 'contract', 'fixtures', `${n}.json`), 'utf8'))
const st = (s: string): TransferState => { const v = TransferStateOps.fromRaw(s); if (v === null) throw new Error(s); return v }
const ev = (s: string): TransferEvent => Object.values(TransferEvent).find((e) => e === s) as TransferEvent

test('fixture: tally', () => { for (const k of fx('tally').cases) assert.deepEqual(tallyOf(k.states.map(st)), k.expect, k.name) })
test('fixture: transitions', () => { for (const k of fx('transitions').cases) assert.equal(TransferStateOps.next(st(k.from), ev(k.event), k.attempts), k.to === null ? null : st(k.to), `${k.from}+${k.event}(${k.attempts})`) })
test('fixture: restore', () => { for (const k of fx('restore').cases) assert.equal(TransferStateOps.recovered(st(k.state), k.attempts), st(k.expect)) })
test('fixture: status-merge', () => { for (const k of fx('status-merge').cases) assert.deepEqual(TransferStateOps.applyingStatus(st(k.state), k.status.delivered, k.status.waitingSeconds, k.status.expiresAt ?? null), { state: st(k.expect.state), waitingSeconds: k.expect.waitingSeconds, expiresAt: k.expect.expiresAt }, k.name) })
test('fixture: delete-warning', () => { for (const k of fx('delete-warning').cases) assert.deepEqual(deleteWarningLevel(k.states.map(st)), k.expect, JSON.stringify(k.states)) })
test('alias: moving → uploading', () => assert.equal(TransferStateOps.fromRaw('moving'), TransferState.uploading))
test('未知状态名解不出来', () => assert.equal(TransferStateOps.fromRaw('does-not-exist'), null))
