import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { tallyOf, tallyTotal, deleteWarningLevel, type QueueState } from '../miniprogram/utils/phase.ts'
import { next, recover, applyStatus } from '../miniprogram/utils/transition.ts'
import { t } from '../miniprogram/utils/i18n.ts'
import { readEnvelope, ApiError } from '../miniprogram/utils/api.ts'
import { formatMoney, shouldHideBalanceRow } from '../miniprogram/utils/money.ts'

const fx = (n: string) => JSON.parse(readFileSync(join(import.meta.dirname, '..', 'contract', 'fixtures', `${n}.json`), 'utf8'))

// billing.json 的 envelope 用例里有一条 code:4010（会话失效），readEnvelope 走到它会
// setSession(null) + wx.reLaunch 去登录页——这里给个最小桩，只为让判读逻辑跑得通，
// 不测 4010 分支本身的跳转行为。
;(globalThis as { wx?: unknown }).wx = {
  getStorageSync: () => null,
  setStorageSync: () => {},
  removeStorageSync: () => {},
  reLaunch: () => {},
}

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

test('fixture: billing envelope — 一律按 kind 解码，缺席的可选键为 null 不是空串', () => {
  const kinds = new Set<string>()
  for (const k of fx('billing').envelope) {
    let caught: ApiError | undefined
    try {
      readEnvelope(200, k.json)
      assert.fail(`应该抛错：${k.name}`)
    } catch (e) {
      assert.ok(e instanceof ApiError, k.name)
      caught = e as ApiError
    }
    assert.equal(caught.code, k.expect.code, k.name)
    assert.equal(caught.message, k.expect.message, k.name)
    assert.equal(caught.kind, k.expect.kind, k.name)
    assert.equal(caught.outTradeNo, k.expect.outTradeNo, k.name)
    if (k.expect.kind) kinds.add(k.expect.kind)
  }
  // 八个 kind 取值都在夹具里出现过，且都能正确解码——不是挑几个测一下就算数
  assert.deepEqual(
    [...kinds].sort(),
    ['ALREADY_PAID', 'DISABLED', 'IDEMPOTENCY_CONFLICT', 'NOT_CONNECTED', 'NOT_FOUND', 'REJECTED', 'REVIEW_ACCOUNT', 'UNAVAILABLE'].sort(),
  )
})

test('fixture: billing balance — 裸对象解码；plan 是计费档位原样透传，不当套餐名映射', () => {
  for (const k of fx('billing').balance) {
    // /billing/balance 是唯一传 { bare: true } 的调用点（N5），其余端点保持严格判读
    const got = readEnvelope<{ balanceCents: number; currency: string; plan: string | null }>(200, k.json, { bare: true })
    // deepEqual 而不是挑字段比对：plan='paid'/'free' 必须原样出现在解码结果里，
    // 不能被映射成套餐名或被丢弃；上游未给这个字段时必须是 null。
    assert.deepEqual(got, k.expect, k.name)
  }
})

test('readEnvelope：没有数字 code 的对象体默认按解析失败处理，只有 bare:true 才当成功（N5）', () => {
  // 不传 bare（登录/项目列表等端点的真实调用方式）：网关 interstitial / 代理注入 /
  // 后端改形状这类没有数字 code 的对象体必须干净地抛「无法解析服务器响应」，
  // 不能被 verifyLoginCode 当成 LoginResult 写进会话，也不能被 myProjects 交给
  // groupByDevice 变成运行时 TypeError。
  for (const body of [{}, { foo: 'bar' }, { sessionId: 'x', user: { id: 1 } }]) {
    assert.throws(() => readEnvelope(200, body), /无法解析服务器响应/, JSON.stringify(body))
  }
  // 唯一的例外：调用点显式声明 bare:true（当前只有 billingBalance）
  assert.deepEqual(readEnvelope(200, { balanceCents: 100, currency: 'CNY' }, { bare: true }), {
    balanceCents: 100,
    currency: 'CNY',
  })
})

test('金额展示：formatMoney 与契约 display 字段逐条对拍（N7，不带千分位、两位小数、符号按 currency 取）', () => {
  for (const k of fx('billing').balance) {
    assert.equal(formatMoney(k.expect.balanceCents, k.expect.currency), k.display, k.name)
  }
})

test('余额行是否渲染：shouldHideBalanceRow 与契约 UI 映射逐条对拍（N2）', () => {
  // NOT_CONNECTED / DISABLED / REVIEW_ACCOUNT 是永远不会自己恢复的终态，整行不渲染
  for (const kind of ['NOT_CONNECTED', 'DISABLED', 'REVIEW_ACCOUNT'] as const) {
    assert.equal(shouldHideBalanceRow(kind), true, kind)
  }
  // 其余（含 kind 缺席）都是可能自己恢复的瞬时故障，显示 balance.unavailable
  for (const kind of ['UNAVAILABLE', 'NOT_FOUND', 'REJECTED', 'ALREADY_PAID', 'IDEMPOTENCY_CONFLICT', null] as const) {
    assert.equal(shouldHideBalanceRow(kind), false, String(kind))
  }
})

test('i18n: 占位符替换与缺键行为', () => {
  assert.equal(t('delete.title', { n: 3 }), '删除 3 件')
  assert.equal(t('tally.failedSuffix', { m: 2 }), '含 2 失败')
  assert.equal(t('no.such.key'), 'no.such.key')
})
