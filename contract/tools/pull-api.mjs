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
const commit = execSync('git rev-parse HEAD', { cwd: server, encoding: 'utf8' }).trim()
mkdirSync(join(root, 'contract', 'api'), { recursive: true })
writeFileSync(join(root, 'contract', 'api', 'mobile-v1.yaml'), yaml)
writeFileSync(join(root, 'contract', 'api', 'PINNED.json'),
  JSON.stringify({ serverCommit: commit, sha256: sha256(yaml), pulledAt: new Date().toISOString() }, null, 2) + '\n')
console.log('pinned', commit.slice(0, 12))
