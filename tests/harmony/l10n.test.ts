import { test } from 'node:test'
import assert from 'node:assert/strict'
import { tr } from '../../harmony/entry/src/main/ets/design/L10n.ets'

test('tr: 占位替换与缺键回显', () => {
  assert.equal(tr('delete.title', { n: 3 }), '删除 3 件')
  assert.equal(tr('tally.failedSuffix', { m: 2 }), '含 2 失败')
  assert.equal(tr('no.such.key'), 'no.such.key')
})
