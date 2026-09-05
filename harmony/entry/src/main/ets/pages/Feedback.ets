import { promptAction, UIContext } from '@kit.ArkUI'
import { tr } from '../design/L10n'
import { ApiError, Unauthorized } from '../model/Envelope'

/**
 * 报错文案。网络失败与业务失败要分开说——用户看到「验证码错误」和看到「网络不通」，
 * 下一步该做什么完全不同。认不出来的一律按网络说：那是最常见的原因，也是用户能自己处理的那种。
 */
export function errorText(e: Object): string {
  if (e instanceof Unauthorized) return tr('error.unauthorized')
  if (e instanceof ApiError) {
    const err: ApiError = e as ApiError
    return err.message.length > 0 ? err.message : tr('error.network')
  }
  return tr('error.network')
}

/**
 * 一次性提示。登录这类一步一停的流程用它，不占版面也不需要用户点掉。
 * 走 UIContext 而不是全局 `promptAction.showToast`：后者已废弃，多窗口下也不知道该弹在哪。
 */
export function toast(ui: UIContext, message: string): void {
  const options: promptAction.ShowToastOptions = { message: message, duration: 2000 }
  ui.getPromptAction().showToast(options)
}
