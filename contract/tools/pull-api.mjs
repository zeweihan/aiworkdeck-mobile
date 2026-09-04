#!/usr/bin/env node
// 从本机服务端仓拉 OpenAPI 副本并写 PINNED.json。用法：CHECKBA_CLOUD_DIR=... node contract/tools/pull-api.mjs
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { join, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execSync } from 'node:child_process'
import { sha256 } from './lib.mjs'

const root = resolve(join(dirname(fileURLToPath(import.meta.url)), '..', '..'))
const server = process.env.CHECKBA_CLOUD_DIR ?? '/Users/zewei/Documents/2024-2044/5-Tech/1-2 checkba_cloud'
const src = join(server, 'backend', 'src', 'main', 'resources', 'openapi', 'mobile-v1.yaml')
const yaml = readFileSync(src, 'utf8')
const git = (cmd) => execSync(cmd, { cwd: server, encoding: 'utf8' }).trim()
const commit = git('git rev-parse HEAD')
// 服务端工作区脏 = 这份 yaml 不在 serverCommit 里，溯源不可复现。写进 note，别让钉版看起来可复现。
const dirty = git('git status --porcelain').length > 0
const note = dirty
  ? `钉的是 ${server} 工作区里尚未提交的内容：serverCommit 只是该工作区的 HEAD，那个 commit 里并没有这份 yaml，照 commit 拉不出同样的 sha256。服务端改动合并后必须重跑 contract/tools/pull-api.mjs 重新钉版。`
  : `钉自 ${server} 的干净工作区，照 serverCommit 可复现。`
mkdirSync(join(root, 'contract', 'api'), { recursive: true })
writeFileSync(join(root, 'contract', 'api', 'mobile-v1.yaml'), yaml)
writeFileSync(join(root, 'contract', 'api', 'PINNED.json'),
  JSON.stringify({ serverCommit: dirty ? `${commit}-dirty` : commit, sha256: sha256(yaml), pulledAt: new Date().toISOString(), note }, null, 2) + '\n')
console.log('pinned', commit.slice(0, 12), dirty ? '(dirty worktree — 合并后须重拉)' : '')
