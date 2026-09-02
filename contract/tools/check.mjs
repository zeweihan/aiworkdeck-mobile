#!/usr/bin/env node
// contract/tools/check.mjs — 契约校验。① 清单 sha ② 引用闭合 ③ 夹具 schema + 与迁移表一致 ④ 生成物未过期 ⑤ API 副本未漂 ⑥ 无内联文案
// 用法：node contract/tools/check.mjs [--root DIR] [--quick]   （--quick 跳过 ⑥）
import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { join, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import Ajv2020 from 'ajv/dist/2020.js'
import { loadContract, manifestFor, DATA_FILES, outputs, sha256 } from './lib.mjs'

const FIXTURES = ['tally', 'transitions', 'status-merge', 'restore', 'delete-warning']

function evalGuard(guard, attempts, state, problems) {
  if (!guard) return true
  if (guard === 'attempts <= maxAutoRetries') return attempts <= state.maxAutoRetries
  problems?.push(`迁移表里有未知 guard「${guard}」：校验器认不出，四端也实现不了`)
  return false
}

/** 参考实现：只在校验器里用，四端各自手写同语义的函数并用夹具对拍 */
export function referenceNext(state, from, event, attempts, problems) {
  const rules = state.transitions.filter((t) => t.from === from && t.event === event)
  if (rules.length === 0) return null
  for (const r of rules) if (evalGuard(r.guard, attempts, state, problems)) return r.to
  return from
}

function checkManifest(c, problems) {
  const expected = manifestFor(c.root, c.manifest.version)
  for (const f of DATA_FILES) {
    if (c.manifest.files[f] !== expected.files[f]) problems.push(`contract.json 里 ${f} 的 sha 过期：改了数据没跑 gen`)
  }
}

/** ② 引用闭合：状态机里的每个名字都必须能在状态表 / 文案词典 / 令牌表里落地 */
function checkReferences(c, problems) {
  const s = c.state
  const states = new Set(s.states)
  const key = (k, where) => {
    if (!c.strings[k]) problems.push(`${where} 指向的文案键 ${k} 不在 strings.json 里`)
  }

  for (const [alias, to] of Object.entries(s.aliases ?? {})) {
    if (!states.has(to)) problems.push(`别名 ${alias} 指向未知状态 ${to}`)
  }

  const phaseOf = new Map()
  for (const [phase, p] of Object.entries(s.phases ?? {})) {
    for (const st of p.states ?? []) {
      if (!states.has(st)) problems.push(`桶 ${phase} 含未知状态 ${st}`)
      if (phaseOf.has(st)) problems.push(`状态 ${st} 同时属于桶 ${phaseOf.get(st)} 与 ${phase}：每个状态只能属一个桶`)
      else phaseOf.set(st, phase)
    }
    key(p.label, `桶 ${phase} 的 label`)
    const [grp, name] = String(p.dot ?? '').split('.')
    if (!c.tokens[grp]?.[name]) problems.push(`桶 ${phase} 的点色令牌 ${p.dot} 不在 tokens.json 里`)
  }
  for (const st of s.states) if (!phaseOf.has(st)) problems.push(`状态 ${st} 不属于任何桶`)

  const [fgrp, fname] = String(s.failedDot ?? '').split('.')
  if (!c.tokens[fgrp]?.[fname]) problems.push(`failedDot 令牌 ${s.failedDot} 不在 tokens.json 里`)

  for (const st of s.states) {
    key(s.stateText?.[st], `stateText[${st}]`)
    key(s.stateDetail?.[st], `stateDetail[${st}]`)
    key(s.whereItIs?.[st], `whereItIs[${st}]`)
  }
  for (const [level, k] of Object.entries(s.deleteWarning?.keys ?? {})) key(k, `deleteWarning.keys.${level}`)
  for (const [cap, v] of Object.entries(c.caps.capabilities ?? {})) {
    if (v.degradedNotice) key(v.degradedNotice, `capabilities.${cap}.degradedNotice`)
  }

  if (s.maxAutoRetries !== (s.retryDelaysMs ?? []).length) {
    problems.push(`maxAutoRetries=${s.maxAutoRetries} 与 retryDelaysMs 的长度 ${(s.retryDelaysMs ?? []).length} 对不上`)
  }

  const events = new Set(s.events ?? [])
  for (const t of s.transitions ?? []) {
    if (!states.has(t.from)) problems.push(`迁移 ${t.from}+${t.event} 的起点是未知状态 ${t.from}`)
    if (!states.has(t.to)) problems.push(`迁移 ${t.from}+${t.event} 的终点是未知状态 ${t.to}`)
    if (!events.has(t.event)) problems.push(`迁移 ${t.from}+${t.event} 的事件不在 events 里`)
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
  if (!Array.isArray(tr.cases)) problems.push('fixtures/transitions.json 没有 cases 数组')
  else for (const k of tr.cases) {
    const got = referenceNext(c.state, k.from, k.event, k.attempts, problems)
    if (got !== k.to) problems.push(`fixtures/transitions.json：${k.from}+${k.event}(attempts=${k.attempts}) 期望 ${k.to}，迁移表推出 ${got}`)
  }
  const rs = JSON.parse(readFileSync(join(c.root, 'contract', 'fixtures', 'restore.json'), 'utf8'))
  if (!Array.isArray(rs.cases)) problems.push('fixtures/restore.json 没有 cases 数组')
  else for (const k of rs.cases) {
    const got = referenceNext(c.state, k.state, 'app_launch', k.attempts, problems) ?? k.state
    if (got !== k.expect) problems.push(`fixtures/restore.json：${k.state}(attempts=${k.attempts}) 期望 ${k.expect}，迁移表推出 ${got}`)
  }
}

function checkGenerated(c, problems) {
  for (const [rel, content] of outputs(c)) {
    const abs = join(c.root, rel)
    if (!existsSync(abs)) { problems.push(`生成物缺失：${rel}（跑 node contract/tools/gen.mjs）`); continue }
    if (readFileSync(abs, 'utf8') !== content) problems.push(`生成物过期或被手改：${rel}（跑 node contract/tools/gen.mjs）`)
  }
}

function checkApiPin(c, problems) {
  const y = join(c.root, 'contract', 'api', 'mobile-v1.yaml')
  const p = join(c.root, 'contract', 'api', 'PINNED.json')
  if (!existsSync(y) || !existsSync(p)) { console.warn('⚠ contract/api 尚无副本，跳过 ④（服务端计划完成后跑 pull-api.mjs）'); return }
  const pinned = JSON.parse(readFileSync(p, 'utf8'))
  if (sha256(readFileSync(y, 'utf8')) !== pinned.sha256) problems.push('contract/api/mobile-v1.yaml 的 sha 与 PINNED.json 不一致：副本被手改，重跑 pull-api.mjs')
}

function walk(dir, exts, skip, out = []) {
  if (!existsSync(dir)) return out
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name)
    if (skip.some((s) => p.includes(s))) continue
    if (e.isDirectory()) walk(p, exts, skip, out)
    else if (exts.some((x) => e.name.endsWith(x))) out.push(p)
  }
  return out
}

const CJK = /[\u4e00-\u9fff]/
/** 带占位的文案拆出的片段短于这个长度就不查了：太短，误报比漏报还烦 */
const MIN_SEGMENT = 3

/** 注释里的中文不算内联文案（说明为什么这么写常常要引用原文） */
function stripComments(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .split('\n')
    .map((l) => l.replace(/\/\/.*$/, ''))
    .join('\n')
}

function checkInline(c, problems) {
  const plain = []      // 无占位：整值查三种引号形态
  const segments = []   // 有占位：按 {x} 切开，中文片段逐行找原样出现（跨插值也能抓到）
  for (const v of Object.values(c.strings)) {
    const zh = v['zh-Hans']
    if (!zh.includes('{')) { plain.push(zh); continue }
    for (const seg of zh.split(/\{\w+\}/)) {
      if (seg.length >= MIN_SEGMENT && CJK.test(seg)) segments.push({ seg, zh })
    }
  }
  const files = [
    ...walk(join(c.root, 'ios', 'Sources'), ['.swift'], ['/Contract/']),
    ...walk(join(c.root, 'miniprogram', 'pages'), ['.ts', '.wxml'], []),
    ...walk(join(c.root, 'miniprogram', 'components'), ['.ts', '.wxml'], []),
    ...walk(join(c.root, 'miniprogram', 'utils'), ['.ts'], ['/utils/contract/']),
  ]
  const appTs = join(c.root, 'miniprogram', 'app.ts')
  if (existsSync(appTs)) files.push(appTs)
  for (const f of files) {
    const rel = f.slice(c.root.length + 1)
    const text = stripComments(readFileSync(f, 'utf8'))
    for (const v of plain) {
      for (const form of [`"${v}"`, `'${v}'`, `>${v}<`]) {
        if (text.includes(form)) problems.push(`内联文案 ${form} 于 ${rel}：改用 strings.json 的键`)
      }
    }
    const seen = new Set()
    for (const line of text.split('\n')) {
      for (const { seg, zh } of segments) {
        if (!line.includes(seg) || seen.has(seg)) continue
        seen.add(seg)
        problems.push(`内联文案片段「${seg}」（出自「${zh}」）于 ${rel}：改用 strings.json 的键`)
      }
    }
  }
}

export function runChecks(root, { quick = false } = {}) {
  const problems = []
  let c
  try { c = loadContract(root) } catch (e) { return { ok: false, problems: [`contract/ 读不进来：${e.message}`] } }
  checkManifest(c, problems)
  checkReferences(c, problems)
  checkFixtures(c, problems)
  checkGenerated(c, problems)
  checkApiPin(c, problems)
  if (!quick) checkInline(c, problems)
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
