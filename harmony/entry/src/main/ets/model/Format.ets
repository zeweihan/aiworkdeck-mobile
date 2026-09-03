const UNITS: string[] = ['B', 'KB', 'MB', 'GB', 'TB']

/**
 * 字节数给人看。1024 进位（与 iOS ByteCountFormatter 的 binary 口径、安卓 Format.kt 同源，
 * 三端显示同一个配额时不会差出 5%）。
 *
 * 小于 10 保留一位小数、10 以上取整：「4.7 GB / 20 GB」有用，「4.73 GB」只是噪音。
 * 纯函数，不碰 @ohos，Node 直接跑。
 */
export function formatBytes(bytes: number): string {
  let v: number = bytes > 0 ? bytes : 0
  let i: number = 0
  while (v >= 1024 && i < UNITS.length - 1) {
    v = v / 1024
    i++
  }
  const n: string = i === 0 ? `${Math.floor(v)}` : (v < 10 ? v.toFixed(1) : v.toFixed(0))
  return `${n} ${UNITS[i]}`
}
