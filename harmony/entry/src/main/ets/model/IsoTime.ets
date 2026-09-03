/**
 * ISO8601 时刻。写用本地时区带偏移（`2026-09-02T17:00:00+08:00`），读宽容——
 * manifest 里的时刻是四端共用的，谁写的都得认。
 *
 * ArkTS 没有 java.time，全部手拼：`Date` 的本地 getter 出年月日时分秒，偏移由
 * `getTimezoneOffset()` 反号得来。
 */

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

/** 本地时刻 + 本地偏移。与安卓 `yyyy-MM-dd'T'HH:mm:ssXXX` 同形。 */
export function formatIso(ms: number): string {
  const d: Date = new Date(ms)
  const offsetMin: number = -d.getTimezoneOffset()     // 东为正
  const sign: string = offsetMin >= 0 ? '+' : '-'
  const abs: number = Math.abs(offsetMin)
  const date: string = `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
  const time: string = `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`
  return `${date}T${time}${sign}${pad2(Math.floor(abs / 60))}:${pad2(abs % 60)}`
}

const ISO: RegExp = /^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?(?:([Zz])|([+-])(\d{2}):?(\d{2}))?$/

/**
 * 宽容解析：带偏移 / 带 `Z` / 带小数秒 / 无偏移（按本地时区补齐）都认。
 * 解不出来给 null——现场宁可显示「时间未知」也不要拿 1970 当采集时刻。
 */
export function parseIso(s: string): number | null {
  const m: RegExpMatchArray | null = s.match(ISO)
  if (m === null) return null
  const year: number = Number.parseInt(m[1], 10)
  const month: number = Number.parseInt(m[2], 10)
  const day: number = Number.parseInt(m[3], 10)
  const hour: number = Number.parseInt(m[4], 10)
  const minute: number = Number.parseInt(m[5], 10)
  const second: number = m[6] === undefined ? 0 : Number.parseInt(m[6], 10)
  const frac: string | undefined = m[7]
  const millis: number = frac === undefined ? 0 : Math.floor(Number.parseFloat(`0.${frac}`) * 1000)
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) return null

  const zulu: string | undefined = m[8]
  const offSign: string | undefined = m[9]
  if (zulu === undefined && offSign === undefined) {
    // 无偏移：按本机时区读，与安卓 LocalDateTime.atZone(systemDefault) 一致
    const local: Date = new Date(year, month - 1, day, hour, minute, second, millis)
    const ms: number = local.getTime()
    return Number.isNaN(ms) ? null : ms
  }
  let offsetMin: number = 0
  if (offSign !== undefined) {
    const oh: number = Number.parseInt(m[10], 10)
    const om: number = Number.parseInt(m[11], 10)
    offsetMin = (oh * 60 + om) * (offSign === '-' ? -1 : 1)
  }
  const utc: number = Date.UTC(year, month - 1, day, hour, minute, second, millis)
  return Number.isNaN(utc) ? null : utc - offsetMin * 60_000
}
