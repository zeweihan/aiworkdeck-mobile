#!/usr/bin/env node
// contract/tools/check.mjs — 契约校验。① 清单 sha ② 夹具 schema + 与迁移表一致 ③ 生成物未过期 ④ API 副本未漂 ⑤ 无内联文案
// 用法：node contract/tools/check.mjs [--root DIR] [--quick]   （--quick 跳过 ⑤）
import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { join, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import Ajv2020 from 'ajv/dist/2020.js'
import { loadContract, manifestFor, DATA_FILES } from './lib.mjs'

const FIXTURES = ['tally', 'transitions', 'status-merge', 'restore', 'delete-warning']

function evalGuard(guard, attempts, state) {
  if (!guard) return true
  if (guard === 'attempts <= maxAutoRetries') return attempts <= state.maxAutoRetries
  throw new Error(`未知 guard: ${guard}`)
}

/** 参考实现：只在校验器里用，四端各自手写同语义的函数并用夹具对拍 */
export function referenceNext(state, from, event, attempts) {
  const rules = state.transitions.filter((t) => t.from === from && t.event === event)
  if (rules.length === 0) return null
  for (const r of rules) if (evalGuard(r.guard, attempts, state)) return r.to
  return from
}

function checkManifest(c, problems) {
  const expected = manifestFor(c.root, c.manifest.version)
  for (const f of DATA_FILES) {
    if (c.manifest.files[f] !== expected.files[f]) problems.push(`contract.json 里 ${f} 的 sha 过期：改了数据没跑 gen`)
  }
}

function checkFixtures(c, problems) {
  const ajv = new Ajv2020({ allErrors: true })
  for (const name of FIXTURES) {
    const schema = JSON.parse(readFileSync(join(c.root, 'contract', 'schema', `${name}.schema.json`), 'utf8'))
    const data = JSON.parse(readFileSync(join(c.root, 'contract', 'fixtures', `${name}.json`), 'utf8'))
    const validate = ajv.compile(schema)
    if (!validate(data)) {
      for (const e of validate.errors) problems.push(`fixtures/${name}.json 不合 schema：${e.instancePath} ${e.message}`)
    }
  }
  // 迁移夹具的期望必须由迁移表推出，夹具不能自说自话
  const tr = JSON.parse(readFileSync(join(c.root, 'contract', 'fixtures', 'transitions.json'), 'utf8'))
  for (const k of tr.cases) {
    const got = referenceNext(c.state, k.from, k.event, k.attempts)
    if (got !== k.to) problems.push(`fixtures/transitions.json：${k.from}+${k.event}(attempts=${k.attempts}) 期望 ${k.to}，迁移表推出 ${got}`)
  }
  const rs = JSON.parse(readFileSync(join(c.root, 'contract', 'fixtures', 'restore.json'), 'utf8'))
  for (const k of rs.cases) {
    const got = referenceNext(c.state, k.state, 'app_launch', k.attempts) ?? k.state
    if (got !== k.expect) problems.push(`fixtures/restore.json：${k.state}(attempts=${k.attempts}) 期望 ${k.expect}，迁移表推出 ${got}`)
  }
}

export function runChecks(root, { quick = false } = {}) {
  const problems = []
  const c = loadContract(root)
  checkManifest(c, problems)
  checkFixtures(c, problems)
  // ③ ④ ⑤ 在后续任务补入
  return { ok: problems.length === 0, problems }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2)
  const i = args.indexOf('--root')
  const root = resolve(i >= 0 ? args[i + 1] : join(dirname(fileURLToPath(import.meta.url)), '..', '..'))
  const r = runChecks(root, { quick: args.includes('--quick') })
  if (!r.ok) { for (const p of r.problems) console.error('✗', p); process.exit(1) }
  console.log('契约校验通过')
}
