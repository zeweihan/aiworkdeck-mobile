#!/usr/bin/env node
// npm prepare 时安装 pre-commit：跑契约校验。worktree 下 hooks 在 common dir。
import { execSync } from 'node:child_process'
import { writeFileSync, mkdirSync, chmodSync } from 'node:fs'
import { join } from 'node:path'

let common
try { common = execSync('git rev-parse --git-common-dir', { encoding: 'utf8' }).trim() } catch { process.exit(0) }
const hooks = join(common, 'hooks')
mkdirSync(hooks, { recursive: true })
const p = join(hooks, 'pre-commit')
writeFileSync(p, `#!/bin/sh
# 由 scripts/install-hooks.mjs 安装。契约校验不过不许提交。
node contract/tools/check.mjs || { echo "契约校验失败，见上。改 contract/ 后跑 node contract/tools/gen.mjs"; exit 1; }
`)
chmodSync(p, 0o755)
console.log('installed', p)
