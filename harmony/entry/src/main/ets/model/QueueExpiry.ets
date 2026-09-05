import { parseIso } from './IsoTime'

/** 只在还剩不到这么多天时说话，平时不打扰。与安卓 `QueueExpiry.kt` 同值。 */
export const EXPIRY_WARN_DAYS: number = 3

const SECONDS_PER_DAY: number = 86400

/**
 * 中转区还剩几天（向上取整，已过期算 0）。解析不出到期时刻就返回 null——
 * 宁可不提醒，也不要凭空造一个日期吓人。
 *
 * 纯函数，不碰 @ohos，Node 直接跑。镜像安卓 `expiryDaysLeft`：两边都按整秒差算，
 * 免得同一件在两台手机上显示的天数差一天。
 */
export function expiryDaysLeft(expiresAt: string | null, nowMs: number): number | null {
  if (expiresAt === null || expiresAt.length === 0) return null
  const at: number | null = parseIso(expiresAt)
  if (at === null) return null
  const seconds: number = Math.floor(at / 1000) - Math.floor(nowMs / 1000)
  if (seconds <= 0) return 0
  return Math.ceil(seconds / SECONDS_PER_DAY)
}
