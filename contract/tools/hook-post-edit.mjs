#!/usr/bin/env node
// Claude Code PostToolUse 钩子：编辑命中契约或生成物路径时立刻校验。失败 exit 2 并把问题写到 stderr（会回灌给模型）。
import { readFileSync } from 'node:fs'
import { runChecks } from './check.mjs'

const WATCH = ['contract/', 'miniprogram/utils/contract/', 'ios/Sources/Contract/', 'miniprogram/styles/tokens.wxss', 'android/contract/', 'harmony/contract/']
let payload = {}
try { payload = JSON.parse(readFileSync(0, 'utf8')) } catch { process.exit(0) }
const fp = String(payload?.tool_input?.file_path ?? '')
if (!WATCH.some((w) => fp.includes(w))) process.exit(0)
const r = runChecks(process.cwd(), { quick: true })
if (!r.ok) {
  console.error('契约校验失败（contract-change skill 步骤 2：先跑 node contract/tools/gen.mjs）：\n' + r.problems.map((p) => ' - ' + p).join('\n'))
  process.exit(2)
}
