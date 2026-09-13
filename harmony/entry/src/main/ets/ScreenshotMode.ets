import { Want } from '@kit.AbilityKit'
import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import BuildProfile from 'BuildProfile'
import { MediaKind, RelayProject } from './model/Capture'
import { Loc } from './model/Loc'
import { TransferState } from './model/TransferState'
import { AccountUser } from './services/ApiTypes'
import { CaptureItem } from './model/Capture'
import { LIBRARY_VIEW_GRID } from './services/Prefs'
import { ServiceLocator } from './services/ServiceLocator'

const DOMAIN: number = 0x0000
const TAG: string = 'ScreenshotMode'

/** `aa start ... --ps awdShots 1`。对位 iOS `-AWDScreenshotMode`、安卓 `--ez awdScreenshot true`。 */
const PARAM_ON: string = 'awdShots'
/** `--ps awdScreen queue`：直接落到某一屏，不靠 uitest 点坐标。 */
const PARAM_SCREEN: string = 'awdScreen'
/** `--ps awdStage 02`：取景区贴哪一张现场照（`resources/rawfile/shots/NN.jpg`）。 */
const PARAM_STAGE: string = 'awdStage'
const STAGE_DEFAULT: string = '03'
const ON: string = '1'

/** 归档日期与种子件的拍摄日期（规格 §3）。模拟器时钟不动，这里给定值，哪天重跑都一样。 */
const ARCHIVE_DATE: string = '2026-09-12'
/** 水印那行时刻：对齐最后一件种子，画面上不会一半 09-12 一半今天。 */
const STAMP_MS: number = Date.parse(`${ARCHIVE_DATE}T15:16:49+08:00`)

interface SeedItem {
  scene: number
  kind: MediaKind
  state: TransferState
  clock: string
  progress: number
}

/** 与 `scripts/store-shots/seed/build-seed.py` 的 ITEMS 同一份表；改一处要顺手对齐另一处。 */
const SEEDS: SeedItem[] = [
  { scene: 1, kind: MediaKind.photo, state: TransferState.arrived, clock: '09:12:04', progress: 1 },
  { scene: 2, kind: MediaKind.photo, state: TransferState.arrived, clock: '09:18:37', progress: 1 },
  { scene: 3, kind: MediaKind.photo, state: TransferState.arrived, clock: '09:41:12', progress: 1 },
  { scene: 4, kind: MediaKind.photo, state: TransferState.arrived, clock: '10:02:55', progress: 1 },
  { scene: 5, kind: MediaKind.photo, state: TransferState.arrived, clock: '10:26:31', progress: 1 },
  { scene: 6, kind: MediaKind.photo, state: TransferState.arrived, clock: '10:58:09', progress: 1 },
  { scene: 7, kind: MediaKind.photo, state: TransferState.arrived, clock: '11:20:44', progress: 1 },
  { scene: 8, kind: MediaKind.photo, state: TransferState.arrived, clock: '11:47:18', progress: 1 },
  { scene: 1, kind: MediaKind.photo, state: TransferState.arrived, clock: '13:05:22', progress: 1 },
  { scene: 2, kind: MediaKind.photo, state: TransferState.arrived, clock: '13:39:50', progress: 1 },
  { scene: 3, kind: MediaKind.audio, state: TransferState.uploaded, clock: '14:02:11', progress: 1 },
  { scene: 4, kind: MediaKind.photo, state: TransferState.uploaded, clock: '14:31:06', progress: 1 },
  { scene: 5, kind: MediaKind.photo, state: TransferState.uploaded, clock: '14:52:40', progress: 1 },
  { scene: 6, kind: MediaKind.video, state: TransferState.uploading, clock: '15:10:27', progress: 0.62 },
  { scene: 7, kind: MediaKind.photo, state: TransferState.uploading, clock: '15:14:03', progress: 0.18 },
  { scene: 8, kind: MediaKind.photo, state: TransferState.waiting, clock: '15:16:49', progress: 0 },
]

const MAIN: RelayProject = {
  deviceId: 'dev-shots',
  deviceName: 'MacBook Pro',
  key: 'p-1',
  name: '华创科技 A 轮尽调',
}

/**
 * 上架截图模式。**只在 debug 构建里成立**——[configure] 第一行看 `BuildProfile.DEBUG`，
 * release 包里 [enabled] 永远是 false，这套假状态跑不起来。
 *
 * 为什么鸿蒙这一端要把种子做进应用里，而安卓是从主机灌：
 * `hdc shell` 是 uid 2000，SELinux 挡在应用沙盒外，`hdc file send` 往
 * `/data/app/el2/100/base/<bundle>/haps/entry/files/` 写一律 permission denied（2026-09-13 实测）。
 * 所以现场照片作为 rawfile（`resources/rawfile/shots/`）随包走，debug 启动时摊进沙盒。
 *
 * 它只解决模拟器上截不出图的四件事：
 * 1. 没有服务端会话也能进主界面；
 * 2. 没有相机——取景区改贴一张静态现场照；没有 GPS——定位给固定的 ±5 米；
 * 3. 没有桌面端——选项目页给三条演示项目，桌面端状态按在线；
 * 4. 图集 / 队列 / 查看器要有真图，所以摊 16 件影像进 `filesDir/FieldEvidence`。
 */
export class ScreenshotMode {
  static enabled: boolean = false
  /** 落到哪一屏：''（首页）/ 'queue' / 'library' / 'viewer' / 'settings'。 */
  static screen: string = ''
  /** 取景区那张静态照的沙盒路径；种子没摊成时为空，界面退回相机预览。 */
  static stagePath: string = ''
  private static stageScene: string = STAGE_DEFAULT

  static readonly loc: Loc = { lat: 31.23041, lon: 121.4737, accuracy: 5 }

  static readonly account: AccountUser = { id: 1, username: 'demo', displayName: '演示账号' }

  /** 选项目页的三条演示项目，名称取自 `docs/specs/2026-09-13-store-assets-design.md` §3。 */
  static readonly projects: RelayProject[] = [
    MAIN,
    { deviceId: 'dev-shots', deviceName: 'MacBook Pro', key: 'p-2', name: '恒达制造 验厂' },
    { deviceId: 'dev-shots', deviceName: 'MacBook Pro', key: 'p-3', name: '南山路 12 号 工程验收' },
  ]

  /** 归档路径与选项目页提示上的日期：截图模式给定值，平时还是今天。 */
  static archiveMs(now: number): number {
    return ScreenshotMode.enabled ? STAMP_MS : now
  }

  static configure(want: Want): void {
    if (!BuildProfile.DEBUG) return
    const params: Record<string, Object> | undefined = want.parameters
    if (params === undefined) return
    const on: Object | undefined = params[PARAM_ON]
    if (typeof on !== 'string' || (on as string) !== ON) return
    ScreenshotMode.enabled = true
    const screen: Object | undefined = params[PARAM_SCREEN]
    ScreenshotMode.screen = typeof screen === 'string' ? screen as string : ''
    const stage: Object | undefined = params[PARAM_STAGE]
    if (typeof stage === 'string') ScreenshotMode.stageScene = stage as string
    hilog.info(DOMAIN, TAG, 'screenshot mode on, screen=%{public}s', ScreenshotMode.screen)
  }

  /**
   * 摊种子。已经摊过就只补一下取景图——每屏都重摊会让 16 件反复变 id，
   * 队列与图集的顺序在两张截图之间就对不上了。
   */
  static async seed(ctx: common.Context): Promise<void> {
    if (!ScreenshotMode.enabled) return
    // 第 8 屏要的就是「还没选项目」那一屏：清掉当前项目，Root 自己路由到选项目页
    const wantsPicker: boolean = ScreenshotMode.screen === 'projects'
    await ServiceLocator.prefs.setSelectedProject(wantsPicker ? null : MAIN)
    await ServiceLocator.prefs.setLibraryView(LIBRARY_VIEW_GRID)
    ScreenshotMode.stagePath = await ScreenshotMode.writeStage(ctx)
    const existing: CaptureItem[] = await ServiceLocator.store.loadAll()
    // 件数正好就是这一批，说明上一次已经摊好了：直接用，别重摊——重摊会换一批新 id，
    // 队列与图集在两张截图之间的顺序就对不上了。
    if (existing.length === SEEDS.length) return
    // 件数对不上说明沙盒里还留着上一次走查的东西（实测模拟器里躺着三条没有项目的录音，
    // 队列页因此挂出一行「其他项目还有 3 件未落盘」）。先清干净再摊。
    if (existing.length > 0) {
      await ServiceLocator.store.remove(existing.map((i: CaptureItem): string => i.id))
    }
    for (const s of SEEDS) {
      await ScreenshotMode.seedOne(ctx, s)
    }
  }

  /** 取景区那张静态照，默认第 3 号场景（会议室尽调现场），`--ps awdStage NN` 可换。 */
  private static async writeStage(ctx: common.Context): Promise<string> {
    const dst: string = `${ctx.filesDir}/screenshot-stage.jpg`
    try {
      ScreenshotMode.writeRawfile(ctx, `shots/${ScreenshotMode.stageScene}.jpg`, dst)
      return dst
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stage write failed: %{public}s', `${e}`)
      return ''
    }
  }

  private static async seedOne(ctx: common.Context, s: SeedItem): Promise<void> {
    const ext: string = s.kind === MediaKind.photo ? 'jpg' : (s.kind === MediaKind.video ? 'mp4' : 'm4a')
    const name: string = s.kind === MediaKind.photo
      ? `shots/${ScreenshotMode.two(s.scene)}.jpg`
      : (s.kind === MediaKind.video ? 'shots/clip.mp4' : 'shots/voice.m4a')
    const tmp: string = `${ctx.cacheDir}/awd-seed-${Date.now()}-${s.scene}.${ext}`
    try {
      ScreenshotMode.writeRawfile(ctx, name, tmp)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'rawfile %{public}s missing: %{public}s', name, `${e}`)
      return
    }
    const at: number = Date.parse(`${ARCHIVE_DATE}T${s.clock}+08:00`)
    try {
      // save() 会把 tmp move 进 media/、算 sha、写 manifest——与真拍一件走的是同一条路
      const id: string = (await ServiceLocator.store.save(s.kind, tmp, at, ScreenshotMode.loc, MAIN)).id
      if (s.state !== TransferState.waiting) {
        await ServiceLocator.store.updateState(id, s.state, s.progress, null)
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'seed item failed: %{public}s', `${e}`)
    }
  }

  private static writeRawfile(ctx: common.Context, name: string, dst: string): void {
    const bytes: Uint8Array = ctx.resourceManager.getRawFileContentSync(name)
    const file: fs.File = fs.openSync(dst, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, bytes.buffer as ArrayBuffer)
    } finally {
      fs.closeSync(file)
    }
  }

  private static two(n: number): string {
    return n < 10 ? `0${n}` : `${n}`
  }
}
