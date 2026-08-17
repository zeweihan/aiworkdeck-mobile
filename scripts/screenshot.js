const automator = require('miniprogram-automator')
const withTimeout = (p, ms, label) =>
  Promise.race([p, new Promise((_, rj) => setTimeout(() => rj(new Error(label + ' 超时 ' + ms + 'ms')), ms))])
;(async () => {
  const mp = await withTimeout(automator.connect({ wsEndpoint: 'ws://localhost:9420' }), 25000, 'connect')
  console.log('connected')
  const page = await withTimeout(mp.currentPage(), 15000, 'currentPage')
  console.log('当前页面:', page.path)
  await new Promise(r => setTimeout(r, 2000))
  await withTimeout(mp.screenshot({ path: 'shot-index.png' }), 20000, 'screenshot')
  console.log('screenshot -> shot-index.png')
  await mp.disconnect()
  process.exit(0)
})().catch(e => { console.error('ERR:', e.message); process.exit(1) })
