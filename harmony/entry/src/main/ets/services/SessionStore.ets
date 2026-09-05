import { asset } from '@kit.AssetStoreKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'SessionStore'
const ALIAS: string = 'sessionId'

function toBytes(s: string): Uint8Array {
  return util.TextEncoder.create('utf-8').encodeInto(s)
}

function fromBytes(b: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(b)
}

function codeOf(e: Object): number {
  const err: BusinessError = e as BusinessError
  return err.code
}

/** alias 匹配用的查询表。RETURN_TYPE=ALL 才会把密文一起带回来。 */
function aliasQuery(withSecret: boolean): asset.AssetMap {
  const q: asset.AssetMap = new Map<asset.Tag, asset.Value>()
  q.set(asset.Tag.ALIAS, toBytes(ALIAS))
  if (withSecret) q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)
  return q
}

/**
 * 会话存储。凭据放系统密钥库（Asset Store Kit），与安卓 EncryptedSharedPreferences 对位（spec H9）。
 *
 * ACCESSIBILITY 取 DEVICE_FIRST_UNLOCKED：开机后用户解过一次锁就能读，锁屏状态下的后台
 * 上传（request.agent 的 BACKGROUND 任务由本进程发起时要带 X-Session-Id）才不会拿不到会话。
 *
 * 待设备验证：Asset Store 在模拟器/未签名调试包上的可用性，本机无镜像无法实测。
 */
export class SessionStore {
  async current(): Promise<string | null> {
    try {
      const found: Array<asset.AssetMap> = await asset.query(aliasQuery(true))
      if (found.length === 0) return null
      const secret: asset.Value | undefined = found[0].get(asset.Tag.SECRET)
      if (secret === undefined) return null
      return fromBytes(secret as Uint8Array)
    } catch (e) {
      if (codeOf(e) !== asset.ErrorCode.NOT_FOUND) {
        hilog.warn(DOMAIN, TAG, 'query failed: %{public}d', codeOf(e))
      }
      return null
    }
  }

  /** 已存在就改写。asset.add 对同 alias 的第二次写会报 DUPLICATED，不是可以忽略的错。 */
  async save(id: string): Promise<void> {
    const attrs: asset.AssetMap = new Map<asset.Tag, asset.Value>()
    attrs.set(asset.Tag.ALIAS, toBytes(ALIAS))
    attrs.set(asset.Tag.SECRET, toBytes(id))
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED)
    try {
      await asset.add(attrs)
    } catch (e) {
      if (codeOf(e) !== asset.ErrorCode.DUPLICATED) throw e as Error
      const update: asset.AssetMap = new Map<asset.Tag, asset.Value>()
      update.set(asset.Tag.SECRET, toBytes(id))
      await asset.update(aliasQuery(false), update)
    }
  }

  async clear(): Promise<void> {
    try {
      await asset.remove(aliasQuery(false))
    } catch (e) {
      if (codeOf(e) !== asset.ErrorCode.NOT_FOUND) {
        hilog.warn(DOMAIN, TAG, 'remove failed: %{public}d', codeOf(e))
      }
    }
  }
}
