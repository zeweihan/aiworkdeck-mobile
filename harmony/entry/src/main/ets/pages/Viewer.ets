import { fileUri } from '@kit.CoreFileKit'
import { AppModel } from '../AppModel'
import { GlassBar, StatusDot } from '../design/Components'
import { tr } from '../design/L10n'
import { Tk } from '../design/Tokens'
import { CaptureItem, MediaKind } from '../model/Capture'
import { formatHms } from '../model/Format'
import { TransferStateOps } from '../model/TransferState'
import { ViewerRequest } from './ViewerRequest'

/** 哈希只露前 12 位：够两边核对是不是同一件，又不至于把整条状态行挤没。 */
const SHA_PREFIX: number = 12
const MAX_ZOOM: number = 5
const DOUBLE_TAP_ZOOM: number = 2.5
const BLACK: string = '#000000'

/**
 * 全屏看大图。左右滑同一天的其他件；照片可缩放，录像与录音交给系统播放器。
 * 只放核对要用的东西：状态、失败原因、哈希前缀、时刻、项目。不做编辑、不做分享——
 * 取证件不该从这一屏流出去。镜像安卓 `ViewerScreen.kt` 与 iOS `ViewerView`。
 *
 * 要看哪一段由 `ViewerRequest` 带进来（只带 id 与起点），条目每次从 `AppModel.items` 取，
 * 所以上传状态在这一屏上是活的，不是一份打开时的快照。
 */
@Component
export struct Viewer {
  stack: NavPathStack = new NavPathStack()

  @State items: CaptureItem[] = []
  @State index: number = 0
  /** 照片缩放。翻页时复位——上一张放大着，下一张进来也是放大的会让人以为拍糊了。 */
  @State zoom: number = 1
  private pinchBase: number = 1
  private token: number = -1

  aboutToAppear(): void {
    this.index = ViewerRequest.index >= 0 ? ViewerRequest.index : 0
    this.token = AppModel.shared.subscribe((): void => this.syncModel())
    this.syncModel()
  }

  aboutToDisappear(): void {
    if (this.token >= 0) AppModel.shared.unsubscribe(this.token)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          Swiper() {
            ForEach(this.items, (it: CaptureItem, i: number): void => {
              this.page(it, i)
            }, (it: CaptureItem): string => it.id)
          }
          .index(this.index)
          .loop(false)
          .indicator(false)
          .width('100%')
          .height('100%')
          .onChange((i: number): void => {
            this.index = i
            this.zoom = 1
            this.pinchBase = 1
          })
        }
        .width('100%')
        .height('100%')

        // 顶栏与底座压在画面上下沿。整层 Transparent：中间那片空白不吃触摸，
        // 缩放与翻页仍然落在下面的画面上
        Column() {
          GlassBar() {
            this.topBar()
          }
          Column()
            .layoutWeight(1)
            .width('100%')
          GlassBar() {
            this.bottomBar()
          }
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(BLACK)
  }

  // MARK: - 画面

  /**
   * 一页。照片双指缩放、双击在 1x 与 2.5x 之间切换；录像与录音都交给 `Video`——
   * 录音没有画面，只出控制条（占位底色 + 音符）。
   *
   * 播放器只在当前页建：几段 1080p 同时解码会把解码器占满。
   */
  @Builder
  page(item: CaptureItem, i: number) {
    Stack() {
      if (item.kind === MediaKind.photo) {
        Image(fileUri.getUriFromPath(item.localPath))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.zoom, y: this.zoom })
          .gesture(GestureGroup(GestureMode.Parallel,
            PinchGesture()
              .onActionStart((): void => {
                this.pinchBase = this.zoom
              })
              .onActionUpdate((e: GestureEvent): void => {
                this.zoom = clampZoom(this.pinchBase * e.scale)
              }),
            TapGesture({ count: 2 })
              .onAction((): void => {
                this.zoom = this.zoom > 1 ? 1 : DOUBLE_TAP_ZOOM
                this.pinchBase = this.zoom
              })))
      } else if (this.index === i) {
        if (item.kind === MediaKind.audio) {
          Text('♪')
            .fontSize(Tk.Ty.hero)
            .fontColor(Tk.D.fgMuted)
            .width('100%')
            .height('100%')
            .textAlign(TextAlign.Center)
        }
        Video({ src: fileUri.getUriFromPath(item.localPath) })
          .controls(true)
          .autoPlay(false)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BLACK)
  }

  // MARK: - 顶栏与底座

  @Builder
  topBar() {
    Row({ space: Tk.Sp.s2 }) {
      Text('✕')
        .fontSize(Tk.Ty.body)
        .fontColor(Tk.D.fg)
        .width(Tk.touchMin)
        .height(Tk.touchMin)
        .textAlign(TextAlign.Center)
        .accessibilityText(tr('common.close'))
        .onClick((): void => {
          this.stack.pop()
        })
      Text(this.pageLabel())
        .fontSize(Tk.Ty.micro)
        .fontColor(Tk.D.fgMuted)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: Tk.Sp.s2, right: Tk.Sp.gutter })
  }

  @Builder
  bottomBar() {
    Column({ space: Tk.Sp.s1 }) {
      Row({ space: Tk.Sp.s1 }) {
        StatusDot({ color: this.dotColor() })
        Text(this.detail())
          .fontSize(Tk.Ty.small)
          .fontColor(Tk.D.fg)
        Text(this.time())
          .fontSize(Tk.Ty.micro)
          .fontColor(Tk.D.fgMuted)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 失败原因不折起来：它是用户唯一能据以判断「要不要重传」的东西
      if (this.failure().length > 0) {
        Text(this.failure())
          .fontSize(Tk.Ty.nano)
          .fontColor(Tk.S.failed)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Row({ space: Tk.Sp.s2 }) {
        Text(this.shaPrefix())
          .fontSize(Tk.Ty.nano)
          .fontColor(Tk.D.fgMuted)
        Text(this.projectName())
          .fontSize(Tk.Ty.nano)
          .fontColor(Tk.D.fgMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: Tk.Sp.gutter, right: Tk.Sp.gutter, top: Tk.Sp.s2, bottom: Tk.Sp.s3,
    })
  }

  // MARK: - 当前这一件

  private current(): CaptureItem | null {
    if (this.items.length === 0) return null
    const i: number = this.index < 0 ? 0 : (this.index >= this.items.length ? this.items.length - 1 : this.index)
    return this.items[i]
  }

  /** 不叫 position：与 CustomComponent 的通用属性方法重名，编不过。 */
  private pageLabel(): string {
    return this.items.length === 0 ? '' : `${this.index + 1} / ${this.items.length}`
  }

  private dotColor(): string {
    const it: CaptureItem | null = this.current()
    return it === null ? Tk.D.rule : Tk.color(TransferStateOps.dotToken(it.state), true)
  }

  private detail(): string {
    const it: CaptureItem | null = this.current()
    return it === null ? '' : TransferStateOps.detail(it.state)
  }

  private failure(): string {
    const it: CaptureItem | null = this.current()
    if (it === null) return ''
    const err: string | null = it.lastError
    return err === null ? '' : err
  }

  private shaPrefix(): string {
    const it: CaptureItem | null = this.current()
    return it === null ? '' : it.manifest.sha256.substring(0, SHA_PREFIX)
  }

  private time(): string {
    const it: CaptureItem | null = this.current()
    return it === null ? '' : formatHms(it.capturedAtMs())
  }

  private projectName(): string {
    const it: CaptureItem | null = this.current()
    if (it === null) return ''
    return it.project === null ? tr('library.unknownProject') : it.project.name
  }

  /**
   * 按 id 从库里取当前的那一份。中途被删掉的件会从这一段里消失，
   * 索引跟着夹回范围内——不留一个指着空处的页码。
   */
  private syncModel(): void {
    const all: CaptureItem[] = AppModel.shared.items
    const picked: CaptureItem[] = []
    for (const id of ViewerRequest.ids) {
      for (const it of all) {
        if (it.id === id) picked.push(it)
      }
    }
    this.items = picked
    if (picked.length === 0) {
      this.index = 0
    } else if (this.index >= picked.length) {
      this.index = picked.length - 1
    }
  }
}

function clampZoom(v: number): number {
  if (v < 1) return 1
  return v > MAX_ZOOM ? MAX_ZOOM : v
}
