import { hilog } from '@kit.PerformanceAnalysisKit'
import { CaptureItem, MediaKind, RelayProject, projectId } from './model/Capture'
import { TransferState } from './model/TransferState'
import { Tally, tallyOf } from './model/TransferTally'
import { isDesktopOnline, otherPendingCount } from './model/AppModelLogic'
import { Unauthorized } from './model/Envelope'
import { AccountUser, MediaUsage } from './services/ApiTypes'
import { Loc } from './services/EvidenceStore'
import { ServiceLocator } from './services/ServiceLocator'

const DOMAIN: number = 0x0000
const TAG: string = 'AppModel'
const HEARTBEAT_MS: number = 60000

/** 根路由的四态，互斥、按顺序判定。boot 是「还没恢复完」，不画任何一屏。 */
export enum Route {
  boot = 'boot',
  login = 'login',
  projects = 'projects',
  home = 'home',
}

/**
 * 全局状态。界面只读它，写入一律经过这里，保证磁盘上的库与屏幕上的画面不会各说各话。
 * 镜像安卓 `AppModel.kt`（与 iOS `AppModel.swift`），差别只在通知界面的机制。
 *
 * **不用状态装饰器**：这是个进程级单例，录音服务（Task 5）与相机（Task 6）都要拿同一份，
 * 而 V1 的 `@State` 会把对象包一层代理、V2 的 `@Trace` 只在 `@ComponentV2` 里被观察，
 * 现有 `design/Components.ets` 又是 V1 组件——混着用是编不过或者「编过了但不刷新」的两头风险。
 * 这里退回最笨也最确定的一招：谁要跟着变，谁 `subscribe` 一个回调，在回调里把值抄进自己的 `@State`。
 */
export class AppModel {
  static readonly shared: AppModel = new AppModel()

  route: Route = Route.boot
  /** 全部影像，跨项目。图集切项目、队列页数「别处还有多少」都要看全量。 */
  items: CaptureItem[] = []
  selectedProject: RelayProject | null = null
  /** 最近一次 myProjects() 成功、且返回里含当前项目那台设备的时刻。 */
  desktopLastSeenMs: number | null = null
  usage: MediaUsage | null = null
  /** 本次登录拿到的账号。冷启动只恢复会话不恢复账号（那要多打一次网络），所以可能为 null。 */
  account: AccountUser | null = null

  private signedIn: boolean = false
  private booted: boolean = false
  private heartbeatId: number = -1
  /** 刷新节流：队列一轮里会连发好几次 onChange，没必要每次都把磁盘重读一遍。 */
  private refreshPending: boolean = false
  private nextToken: number = 1
  private readonly listeners: Map<number, () => void> = new Map<number, () => void>()

  /** 订阅状态变化。返回的号用来退订（页面 aboutToDisappear 里退，免得回调打在已销毁的组件上）。 */
  subscribe(cb: () => void): number {
    const token: number = this.nextToken
    this.nextToken = token + 1
    this.listeners.set(token, cb)
    return token
  }

  unsubscribe(token: number): void {
    this.listeners.delete(token)
  }

  // MARK: - 启动

  /**
   * 冷启动恢复。只判断本地「有没有会话」，会话是否还有效交给第一次真实请求的 4010——
   * 启动多打一次网络请求会让离线开 App 卡住，而离线拍照正是主场景。
   */
  async bootstrap(): Promise<void> {
    if (this.booted) return
    this.booted = true
    try {
      await ServiceLocator.store.sweepOrphans()
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'sweepOrphans failed: %{public}s', messageOf(e))
    }
    try {
      this.signedIn = await ServiceLocator.backend.hasSession()
    } catch (e) {
      this.signedIn = false
    }
    this.selectedProject = await this.readSelectedProject()
    this.route = this.routeForState()
    this.emit()
    await this.refresh()
    ServiceLocator.queue.onChange = (): void => {
      this.scheduleRefresh()
    }
    this.startHeartbeat()
  }

  /**
   * 上传自愈心跳（dev-board#241 的鸿蒙对应）：滞留的「传输中」与失败件不能等用户来点，
   * 现场拍完手机就揣兜里了。顺带刷新桌面端在线判定。
   */
  private startHeartbeat(): void {
    if (this.heartbeatId >= 0) return
    this.heartbeatId = setInterval((): void => {
      this.beat().catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'heartbeat failed: %{public}s', messageOf(e))
      })
    }, HEARTBEAT_MS)
  }

  private stopHeartbeat(): void {
    if (this.heartbeatId < 0) return
    clearInterval(this.heartbeatId)
    this.heartbeatId = -1
  }

  private async beat(): Promise<void> {
    if (!this.signedIn) return
    await ServiceLocator.queue.autoKick()
    await this.refreshDesktopOnline()
    await this.refresh()
    if (ServiceLocator.queue.consumeUnauthorized()) await this.signOut()
  }

  /** 项目列表来自桌面端的定时上报：能读到且里面有当前项目那台机器，就认为它此刻开着。 */
  private async refreshDesktopOnline(): Promise<void> {
    const current: RelayProject | null = this.selectedProject
    if (current === null) return
    try {
      const projects: RelayProject[] = await ServiceLocator.backend.myProjects()
      const seen: boolean = projects.some((p: RelayProject): boolean => p.deviceId === current.deviceId)
      if (seen) {
        this.desktopLastSeenMs = Date.now()
        this.emit()
      }
    } catch (e) {
      if (e instanceof Unauthorized) {
        await this.signOut()
        return
      }
      // 读不到不等于对面不在——网络抖一下就宣布离线是噪音，交给三分钟窗口自己过期
      hilog.info(DOMAIN, TAG, 'myProjects skipped: %{public}s', messageOf(e))
    }
  }

  // MARK: - 账号与项目

  /** 登录成功。已经选过项目的（换手机重装之外的情形）直接回取景器，不再问一遍。 */
  async didLogin(user: AccountUser): Promise<void> {
    this.signedIn = true
    this.account = user
    this.selectedProject = await this.readSelectedProject()
    this.route = this.routeForState()
    this.emit()
    this.startHeartbeat()
    await this.refresh()
  }

  async selectProject(p: RelayProject): Promise<void> {
    await ServiceLocator.prefs.setSelectedProject(p)
    this.selectedProject = p
    this.desktopLastSeenMs = Date.now()
    this.route = Route.home
    this.emit()
    await this.refresh()
    await ServiceLocator.queue.kick()
  }

  /**
   * 退出登录。**不清本地影像**——退出不等于放弃已经拍到的东西，现场是不可复现的，
   * 登出就删是灾难性的默认。
   */
  async signOut(): Promise<void> {
    await ServiceLocator.backend.logout()
    await ServiceLocator.prefs.setSelectedProject(null)
    this.stopHeartbeat()
    this.signedIn = false
    this.account = null
    this.selectedProject = null
    this.desktopLastSeenMs = null
    this.usage = null
    this.route = Route.login
    this.emit()
    await this.refresh()
  }

  /**
   * 注销账号。删的是**云端**的账号与数据；手机本地的影像不动——理由同 signOut。
   * 各应用商店的账号删除要求（与 App Store 5.1.1(v)）都指向这个入口。
   */
  async deleteAccount(): Promise<void> {
    await ServiceLocator.backend.deleteAccount()
    await this.signOut()
  }

  /** 云端中转区用量。设置页进页面拉一次；失败让调用方自己决定怎么显示（那里用「—」占位）。 */
  async mediaUsage(): Promise<MediaUsage> {
    const u: MediaUsage = await ServiceLocator.backend.mediaUsage()
    this.usage = u
    this.emit()
    return u
  }

  // MARK: - 影像

  /**
   * 落一件。顺序是「先进库、再存相册、最后排上传」：库是唯一可信的那一份，
   * 相册与上传都从它派生，任何一条失败都不该回滚已经落好的原件。
   */
  async store(kind: MediaKind, tempPath: string, capturedAtMs: number, loc: Loc | null): Promise<CaptureItem> {
    const item: CaptureItem = await ServiceLocator.store.save(
      kind, tempPath, capturedAtMs, loc, this.selectedProject)
    await this.refresh()
    // 存相册（AlbumSaver）挂在这里，Task 6 接相机时装上：它与上传是两条互不影响的链
    ServiceLocator.queue.kick().catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'kick failed: %{public}s', messageOf(e))
    })
    return item
  }

  /** 从磁盘重读一遍。读不出来不清空界面——宁可显示上一次的状态。 */
  async refresh(): Promise<void> {
    try {
      this.items = await ServiceLocator.store.loadAll()
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'loadAll failed: %{public}s', messageOf(e))
      return
    }
    this.emit()
  }

  /** 三段计数只数当前项目——进度跟着项目走。 */
  tally(): Tally {
    return tallyOf(this.currentItems().map((i: CaptureItem): TransferState => i.state))
  }

  currentItems(): CaptureItem[] {
    const selected: string | null = this.selectedProject === null ? null : projectId(this.selectedProject)
    return this.items.filter((i: CaptureItem): boolean =>
      (i.project === null ? null : projectId(i.project)) === selected)
  }

  otherPending(): number {
    return otherPendingCount(this.items, this.selectedProject)
  }

  desktopOnline(): boolean {
    return isDesktopOnline(this.desktopLastSeenMs, Date.now())
  }

  /** 回到前台：磁盘可能被后台上传任务改过，队列也可能停在半路。 */
  onForeground(): void {
    if (!this.booted) return
    this.refresh().catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'foreground refresh failed: %{public}s', messageOf(e))
    })
    ServiceLocator.queue.autoKick().catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'foreground autoKick failed: %{public}s', messageOf(e))
    })
  }

  // MARK: - 内部

  private routeForState(): Route {
    if (!this.signedIn) return Route.login
    return this.selectedProject === null ? Route.projects : Route.home
  }

  private async readSelectedProject(): Promise<RelayProject | null> {
    try {
      return await ServiceLocator.prefs.selectedProject()
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'selectedProject failed: %{public}s', messageOf(e))
      return null
    }
  }

  /** 队列一轮里会连发好几次 onChange；合并成一次磁盘重读。 */
  private scheduleRefresh(): void {
    if (this.refreshPending) return
    this.refreshPending = true
    setTimeout((): void => {
      this.refreshPending = false
      this.refresh().catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'scheduled refresh failed: %{public}s', messageOf(e))
      })
    }, 0)
  }

  private emit(): void {
    for (const cb of this.listeners.values()) cb()
  }
}

function messageOf(e: Object): string {
  if (e instanceof Error) {
    const err: Error = e as Error
    return err.message.length > 0 ? err.message : err.name
  }
  return `${e}`
}
