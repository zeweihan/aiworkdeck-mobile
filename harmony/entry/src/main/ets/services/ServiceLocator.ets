import { common } from '@kit.AbilityKit'
import { Backend } from './Backend'
import { EvidenceStore } from './EvidenceStore'
import { Prefs } from './Prefs'
import { SessionStore } from './SessionStore'
import { UploadQueue } from './UploadQueue'
import { Uploader } from './Uploader'
import { DeviceFacts, deviceFacts } from './DeviceFacts'

/** 单站大陆服务端（spec §0）。四端同一个地址，端上不给切换入口。 */
export const BASE_URL: string = 'https://addin.aiworkdeck.com'

function need<T>(v: T | null): T {
  if (v === null) throw new Error('ServiceLocator.init(ctx) has not run')
  return v
}

/**
 * 进程级服务装配点，`EntryAbility.onCreate` 里 `init(ctx)` 一次。
 * ArkTS 没有 DI，页面与后台任务都从这里取同一批实例——EvidenceStore 的串行锁与
 * UploadQueue 的单飞标志都是实例状态，装配两遍就等于两条互不知情的队列。
 *
 * 字段写成「私有可空 + 只读取值器」而不是 `static x!: T`：ArkTS 不接受静态字段上的
 * 明确赋值断言（10505001），而未装配就取用是编程错误，宁可当场抛也不要拿到 null 再往下走。
 */
export class ServiceLocator {
  private static ctxRef: common.Context | null = null
  private static sessionRef: SessionStore | null = null
  private static prefsRef: Prefs | null = null
  private static factsRef: DeviceFacts | null = null
  private static backendRef: Backend | null = null
  private static storeRef: EvidenceStore | null = null
  private static uploaderRef: Uploader | null = null
  private static queueRef: UploadQueue | null = null

  static get ctx(): common.Context {
    return need<common.Context>(ServiceLocator.ctxRef)
  }

  static get session(): SessionStore {
    return need<SessionStore>(ServiceLocator.sessionRef)
  }

  static get prefs(): Prefs {
    return need<Prefs>(ServiceLocator.prefsRef)
  }

  static get facts(): DeviceFacts {
    return need<DeviceFacts>(ServiceLocator.factsRef)
  }

  static get backend(): Backend {
    return need<Backend>(ServiceLocator.backendRef)
  }

  static get store(): EvidenceStore {
    return need<EvidenceStore>(ServiceLocator.storeRef)
  }

  static get uploader(): Uploader {
    return need<Uploader>(ServiceLocator.uploaderRef)
  }

  static get queue(): UploadQueue {
    return need<UploadQueue>(ServiceLocator.queueRef)
  }

  static init(ctx: common.Context): void {
    if (ServiceLocator.ctxRef !== null) return
    const session: SessionStore = new SessionStore()
    const prefs: Prefs = new Prefs(ctx)
    const facts: DeviceFacts = deviceFacts(ctx)
    const backend: Backend = new Backend(BASE_URL, session)
    const store: EvidenceStore = new EvidenceStore(`${ctx.filesDir}/FieldEvidence`, facts)
    const uploader: Uploader = new Uploader(ctx, BASE_URL, session, prefs)
    ServiceLocator.sessionRef = session
    ServiceLocator.prefsRef = prefs
    ServiceLocator.factsRef = facts
    ServiceLocator.backendRef = backend
    ServiceLocator.storeRef = store
    ServiceLocator.uploaderRef = uploader
    ServiceLocator.queueRef = new UploadQueue(store, uploader, backend)
    ServiceLocator.ctxRef = ctx
  }

  static isReady(): boolean {
    return ServiceLocator.ctxRef !== null
  }
}
