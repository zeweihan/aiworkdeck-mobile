/**
 * 录音时钟。纯逻辑，不碰 AVRecorder：录音舞台的计时器与常驻通知的文案都从这里派生，
 * 两处显示不会各算各的。与 iOS `RecordingClock.swift` 同名同语义。
 *
 * 系统中断（来电、闹钟）时录音机被暂停，当前运行段的秒数并入 elapsedBase；续录时另起一段。
 * 时刻参数一律毫秒，elapsed 返回秒。
 */
export class RecordingClock {
  /** 当前运行段之前累计的秒数 */
  elapsedBase: number = 0
  /** 当前运行段的起点（毫秒）；null = 未开始或中断中 */
  resumedAt: number | null = null
  paused: boolean = false

  start(at: number): void {
    this.elapsedBase = 0
    this.resumedAt = at
    this.paused = false
  }

  /** 重复调用幂等：系统可能连发两次中断开始，第二次不能再扣一段。 */
  interrupt(at: number): void {
    const from: number | null = this.resumedAt
    if (from === null) return
    this.elapsedBase += Math.max(0, (at - from) / 1000)
    this.resumedAt = null
    this.paused = true
  }

  resume(at: number): void {
    if (!this.paused) return
    this.resumedAt = at
    this.paused = false
  }

  elapsed(at: number): number {
    const from: number | null = this.resumedAt
    return this.elapsedBase + (from === null ? 0 : Math.max(0, (at - from) / 1000))
  }
}
