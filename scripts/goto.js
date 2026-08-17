const automator = require('miniprogram-automator')
const T = (p, ms, l) => Promise.race([p, new Promise((_, r) => setTimeout(() => r(new Error(l + ' timeout')), ms))])
;(async () => {
  const mp = await T(automator.connect({ wsEndpoint: 'ws://localhost:9420' }), 25000, 'connect')
  await T(mp.reLaunch('/' + process.argv[2]), 15000, 'reLaunch')
  const p = await T(mp.currentPage(), 10000, 'currentPage')
  console.log('now:', p.path)
  await mp.disconnect(); process.exit(0)
})().catch(e => { console.error('ERR:', e.message); process.exit(1) })
