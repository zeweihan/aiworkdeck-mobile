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

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

/**
 * 录制计时 mm:ss。超过一小时也继续往上加分钟，不进位到小时——现场没有那么长的单段，
 * 「61:01」比「01:01:01」少一次心算。与安卓 `WatermarkFormat.duration` 同口径。
 *
 * 秒数向下取整：秒表跳到 1 应该是录满 1 秒之后，不是 0.6 秒就跳。
 */
export function formatClock(seconds: number): string {
  const s: number = seconds > 0 ? Math.floor(seconds) : 0
  return `${pad2(Math.floor(s / 60))}:${pad2(s % 60)}`
}

/**
 * 本机时区的时刻。格子上只到分（一格里塞不下更多），查看器到秒——核对取证件要精确到那一下。
 * 与安卓 `LibraryTime.clock / precise` 同口径。
 */
export function formatHm(ms: number): string {
  const d: Date = new Date(ms)
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`
}

export function formatHms(ms: number): string {
  const d: Date = new Date(ms)
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`
}

/**
 * 本机时区的日期 yyyy-MM-dd。归档路径里的那个日期（`archive.path` 的 `{date}`），
 * 用户看得见且要与桌面端的归档目录同形，所以只留这一份实现——两处各写一份迟早漂移。
 */
export function formatDay(ms: number): string {
  const d: Date = new Date(ms)
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
}
