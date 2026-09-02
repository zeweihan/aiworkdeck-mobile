#!/usr/bin/env node
// npm prepare 时安装 pre-commit：跑契约校验。worktree 下 hooks 在 common dir。
import { execSync } from 'node:child_process'
import { writeFileSync, mkdirSync, chmodSync, existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const MARK = '由 scripts/install-hooks.mjs 安装'

let common
try {
  // stdio 的 stderr 丢掉：非 git 目录（比如 npm 装成依赖）不该往控制台吐 fatal
  common = execSync('git rev-parse --git-common-dir', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
} catch { process.exit(0) }
const hooks = join(common, 'hooks')
mkdirSync(hooks, { recursive: true })
const p = join(hooks, 'pre-commit')
if (existsSync(p) && !readFileSync(p, 'utf8').includes(MARK)) {
  console.warn(`⚠ ${p} 已存在且不是本脚本装的，原样保留。请自行加一行 node contract/tools/check.mjs`)
  process.exit(0)
}
writeFileSync(p, `#!/bin/sh
# ${MARK}。契约校验不过不许提交。
node contract/tools/check.mjs || { echo "契约校验失败，见上。改 contract/ 后跑 node contract/tools/gen.mjs"; exit 1; }
`)
chmodSync(p, 0o755)
console.log('installed', p)
