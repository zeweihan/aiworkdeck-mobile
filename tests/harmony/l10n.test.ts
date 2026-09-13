import { test } from 'node:test'
import assert from 'node:assert/strict'
import { tr } from '../../harmony/entry/src/main/ets/design/L10n.ets'
import { ContractCapabilities } from '../../harmony/contract/Index.ets'

test('tr: 占位替换与缺键回显', () => {
  assert.equal(tr('delete.title', { n: 3 }), '删除 3 件')
  assert.equal(tr('tally.failedSuffix', { m: 2 }), '含 2 失败')
  assert.equal(tr('no.such.key'), 'no.such.key')
})

// 鸿蒙没有支付通道（dev-board 鸿蒙卡），契约把 recharge 记成 'external'：设置页放入口、
// 点开只说明去哪儿充。这条钉住两件事——能力值没被悄悄改成某个真通道（改了界面就得真能下单），
// 以及那两句说明确实在词典里（缺键时 tr 原样回显键名，界面上就是一行 'recharge.external.title'）。
test('设置页的充值说明取自契约：能力是 external，文案在词典里', () => {
  assert.equal(ContractCapabilities.recharge, 'external')
  assert.equal(tr('recharge.entry'), '充值')
  assert.equal(tr('recharge.external.title'), 'App 内充值开通中')
  assert.equal(tr('recharge.external.body'), '请先在微信小程序「AI WorkDeck」的「我的 → 充值」里充值，余额四端通用')
})
