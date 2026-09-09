/**
 * 体验版/开发版诊断（dev-board#536/#427 真机定位）：真机上没有控制台，脚本错误、相机错误、
 * 支付错误一律用原生弹窗把原文亮出来；正式版只打 console，不打扰用户。
 */
export function isTrialBuild(): boolean {
  try {
    const v = wx.getAccountInfoSync().miniProgram.envVersion
    return v === 'trial' || v === 'develop'
  } catch {
    return false
  }
}

export function reportDiag(title: string, detail: string): void {
  console.error(`[diag] ${title}: ${detail}`)
  if (!isTrialBuild()) return
  wx.showModal({ title, content: detail.slice(0, 600), showCancel: false })
}
