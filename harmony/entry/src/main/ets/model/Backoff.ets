/**
 * 自动重试退避。首败等 60 秒，之后逐次翻倍，封顶 15 分钟；一次成功就复位。
 * 语义照抄安卓 UploadQueue 的退避段（backoffSeconds / nextAutoKickAt）。
 */
export class Backoff {
  seconds: number = 60
  nextAt: number = 0

  onFailure(now: number): void {
    this.nextAt = now + this.seconds * 1000
    this.seconds = Math.min(this.seconds * 2, 900)
  }

  reset(): void {
    this.seconds = 60
  }
}
