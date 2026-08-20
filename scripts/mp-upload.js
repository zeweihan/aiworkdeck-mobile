/**
 * 小程序上传（miniprogram-ci）。用法：
 *   node scripts/mp-upload.js <版本号> [备注]
 *
 * 前置（维护者手工，一次性）：
 * 1. 微信公众平台 → 开发管理 → 开发设置 → 小程序代码上传密钥，下载后存
 *    ~/.aiworkdeck/mp-upload-key.pem（0600），或用环境变量 MP_UPLOAD_KEY 指定路径。
 * 2. 同页把本机出口 IP 加入上传白名单（或关闭 IP 白名单）。
 *
 * 上传成功后到公众平台「版本管理」把该版本设为体验版/提审。
 */
const path = require('path')
const os = require('os')
const fs = require('fs')
const ci = require('miniprogram-ci')

const root = path.resolve(__dirname, '..')
const version = process.argv[2]
const desc = process.argv[3] || `上传于 ${new Date().toISOString().slice(0, 16).replace('T', ' ')}`
if (!version) {
  console.error('用法：node scripts/mp-upload.js <版本号> [备注]')
  process.exit(1)
}

const keyPath = process.env.MP_UPLOAD_KEY || path.join(os.homedir(), '.aiworkdeck', 'mp-upload-key.pem')
if (!fs.existsSync(keyPath)) {
  console.error(`找不到上传密钥：${keyPath}\n先在微信公众平台生成代码上传密钥并存到该路径（见本文件头部注释）。`)
  process.exit(1)
}

const appid = JSON.parse(fs.readFileSync(path.join(root, 'project.config.json'), 'utf8')).appid

async function main() {
  const project = new ci.Project({
    appid,
    type: 'miniProgram',
    projectPath: root,
    privateKeyPath: keyPath,
    ignores: ['node_modules/**/*', 'ios/**/*', 'docs/**/*', 'scripts/**/*', 'fastlane/**/*'],
  })
  const result = await ci.upload({
    project,
    version,
    desc,
    setting: { es6: true, enhance: true, minify: true },
    onProgressUpdate: () => {},
  })
  console.log(`上传完成：v${version}（appid ${appid}）`)
  if (result && result.subPackageInfo) {
    for (const p of result.subPackageInfo) console.log(`  ${p.name}: ${(p.size / 1024).toFixed(0)} KB`)
  }
}

main().catch((e) => {
  console.error(`上传失败：${e.message || e}`)
  process.exit(1)
})
