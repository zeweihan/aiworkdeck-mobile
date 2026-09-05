import { deviceInfo } from '@kit.BasicServicesKit'
import { bundleManager, common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'DeviceFacts'

/** 落盘 manifest 里记的设备指纹，与 iOS / 安卓 DeviceFacts 同形。 */
export interface DeviceFacts {
  model: string
  osVersion: string
  appVersion: string
}

/**
 * 本机指纹。机型优先取 marketName（用户认得的「Pura 90 Pro」），拿不到才退 productModel
 * （内部代号）；系统版本取 osFullName；应用版本取包信息里的 versionName。
 *
 * ctx 目前用不到（getBundleInfoForSelfSync 不需要上下文），保留在签名里是为了让调用方
 * 不必知道这件事——日后换成 ctx.applicationInfo 之类不用改调用点。
 */
export function deviceFacts(ctx: common.Context): DeviceFacts {
  let model: string = ''
  let osVersion: string = ''
  try {
    model = deviceInfo.marketName
    if (model.length === 0) model = deviceInfo.productModel
    osVersion = deviceInfo.osFullName
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'deviceInfo unavailable: %{public}s', (e as Error).message)
  }
  let appVersion: string = ''
  try {
    const info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
    appVersion = info.versionName
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'bundle info unavailable: %{public}s', (e as Error).message)
  }
  const facts: DeviceFacts = { model: model, osVersion: osVersion, appVersion: appVersion }
  return facts
}
