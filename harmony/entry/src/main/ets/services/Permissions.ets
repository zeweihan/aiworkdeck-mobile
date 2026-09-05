import { abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'Permissions'

export const PERM_CAMERA: Permissions = 'ohos.permission.CAMERA'
export const PERM_MICROPHONE: Permissions = 'ohos.permission.MICROPHONE'
export const PERM_LOCATION: Permissions = 'ohos.permission.LOCATION'
export const PERM_APPROX_LOCATION: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION'

/**
 * 当前是否已授某项权限。同步问，因为界面每次重画都要据此决定画取景还是画「去设置」，
 * 异步一问就会闪一下。
 *
 * `checkAccessTokenSync(tokenID, permissionName)`：`@ohos.abilityAccessCtrl.d.ts:259`；
 * 自己的 tokenId 走 `bundleManager.getBundleInfoForSelfSync(GET_BUNDLE_INFO_WITH_APPLICATION)`
 * 的 `appInfo.accessTokenId`（`bundleManager/ApplicationInfo.d.ts:195`）。
 */
export function hasPermission(perm: Permissions): boolean {
  try {
    const info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
    const status: abilityAccessCtrl.GrantStatus =
      abilityAccessCtrl.createAtManager().checkAccessTokenSync(info.appInfo.accessTokenId, perm)
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'checkAccessTokenSync failed: %{public}s', `${e}`)
    return false
  }
}
