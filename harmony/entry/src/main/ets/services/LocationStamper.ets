import { geoLocationManager } from '@kit.LocationKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { Loc } from '../model/Loc'
import { hasPermission, PERM_APPROX_LOCATION, PERM_LOCATION } from './Permissions'

const DOMAIN: number = 0x0000
const TAG: string = 'LocationStamper'

/** 8 秒。按下快门到落库不能等 GPS，超时就没有坐标，不是没有这一件。 */
const TIMEOUT_MS: number = 8000

/**
 * 单次定位。拿不到就返回 null：没有坐标的取证件仍然是取证件，编一个坐标才是灾难
 * （与安卓 `LocationStamper.kt`、iOS 同）。
 *
 * 权限不在这里要——取景页进来时一次问齐相机 / 麦克风 / 定位，这里只看有没有。
 */
export class LocationStamper {
  async current(): Promise<Loc | null> {
    if (!hasPermission(PERM_LOCATION) && !hasPermission(PERM_APPROX_LOCATION)) return null
    // getCurrentLocation(request)：@ohos.geoLocationManager.d.ts:472；
    // FIRST_FIX（同上 :2787）= 拿到第一个定位就返回，别为了精度多等几秒
    const request: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
      timeoutMs: TIMEOUT_MS,
    }
    try {
      const at: geoLocationManager.Location = await geoLocationManager.getCurrentLocation(request)
      const loc: Loc = { lat: at.latitude, lon: at.longitude, accuracy: at.accuracy }
      return loc
    } catch (e) {
      // 室内拿不到定位是常态，不是错误
      hilog.info(DOMAIN, TAG, 'no fix: %{public}s', `${e}`)
      return null
    }
  }
}
