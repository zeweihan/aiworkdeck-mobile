import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, mkdtempSync, cpSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { loadContract, sha256, DATA_FILES } from '../contract/tools/lib.mjs'
import { runChecks } from '../contract/tools/check.mjs'

const ROOT = join(import.meta.dirname, '..')

function tempCopy(): string {
  const dir = mkdtempSync(join(tmpdir(), 'awd-contract-'))
  cpSync(join(ROOT, 'contract'), join(dir, 'contract'), { recursive: true })
  return dir
}

test('contract.json 的 sha 与四个数据文件一致', () => {
  const c = loadContract(ROOT)
  for (const f of DATA_FILES) {
    const actual = sha256(readFileSync(join(ROOT, 'contract', f), 'utf8'))
    assert.equal(c.manifest.files[f], actual, `${f} 的 sha 过期，跑 node contract/tools/gen.mjs`)
  }
})

test('状态机引用闭合', () => {
  const { state, strings, tokens } = loadContract(ROOT)
  const states = new Set(state.states)
  for (const [alias, to] of Object.entries(state.aliases)) {
    assert.ok(states.has(to), `别名 ${alias} 指向未知状态 ${to}`)
  }
  const covered = new Set()
  for (const [phase, p] of Object.entries(state.phases)) {
    for (const s of p.states) { assert.ok(states.has(s), `${phase} 含未知状态 ${s}`); covered.add(s) }
    assert.ok(strings[p.label], `桶 ${phase} 的文案键 ${p.label} 不存在`)
    const [grp, name] = p.dot.split('.')
    assert.ok(tokens[grp]?.[name], `桶 ${phase} 的点色令牌 ${p.dot} 不存在`)
  }
  assert.deepEqual([...covered].sort(), [...states].sort(), '每个状态必须恰属一个桶')
  for (const s of state.states) {
    assert.ok(strings[state.stateText[s]], `stateText[${s}] 文案键不存在`)
    assert.ok(strings[state.whereItIs[s]], `whereItIs[${s}] 文案键不存在`)
  }
  for (const t of state.transitions) {
    assert.ok(states.has(t.from) && states.has(t.to), `迁移 ${t.from}→${t.to} 含未知状态`)
  }
  assert.equal(state.maxAutoRetries, state.retryDelaysMs.length)
})

test('check：现状全绿（quick）', () => {
  const r = runChecks(ROOT, { quick: true })
  assert.deepEqual(r.problems, [])
  assert.equal(r.ok, true)
})

test('check：数据文件改了没跑 gen → sha 不一致要红', () => {
  const dir = tempCopy()
  const p = join(dir, 'contract', 'strings.json')
  const s = JSON.parse(readFileSync(p, 'utf8'))
  s['phase.landed']['zh-Hans'] = '已归档'
  writeFileSync(p, JSON.stringify(s, null, 2))
  const r = runChecks(dir, { quick: true })
  assert.ok(r.problems.some((m) => m.includes('strings.json') && m.includes('sha')), r.problems.join('\n'))
})

test('check：坏夹具要红', () => {
  const dir = tempCopy()
  const p = join(dir, 'contract', 'fixtures', 'tally.json')
  writeFileSync(p, JSON.stringify({ cases: [{ name: 'x', states: ['flying'], expect: { uploading: 0, failed: 0, staged: 0, landed: 0, total: 0 } }] }))
  const r = runChecks(dir, { quick: true })
  assert.ok(r.problems.some((m) => m.includes('fixtures/tally.json')), r.problems.join('\n'))
})

test('check：夹具期望必须与迁移表一致', () => {
  const dir = tempCopy()
  const p = join(dir, 'contract', 'fixtures', 'transitions.json')
  const f = JSON.parse(readFileSync(p, 'utf8'))
  f.cases[0].to = 'arrived'  // waiting + kick 应为 uploading
  writeFileSync(p, JSON.stringify(f))
  const r = runChecks(dir, { quick: true })
  assert.ok(r.problems.some((m) => m.includes('transitions.json') && m.includes('迁移表')), r.problems.join('\n'))
})
