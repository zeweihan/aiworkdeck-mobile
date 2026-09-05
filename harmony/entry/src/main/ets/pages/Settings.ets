import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppModel } from '../AppModel'
import { tr } from '../design/L10n'
import { Tk } from '../design/Tokens'
import { formatBytes } from '../model/Format'
import { RelayProject } from '../model/Capture'
import { Unauthorized } from '../model/Envelope'
import { AccountUser, MediaUsage } from '../services/ApiTypes'
import { BASE_URL, ServiceLocator } from '../services/ServiceLocator'
import { errorText, toast } from './Feedback'

const DOMAIN: number = 0x0000
const TAG: string = 'Settings'

/** 用量读不到时的占位。一条「—」比一行报错更符合这行信息的分量。 */
const DASH: string = '—'

/** 服务器地址只显示主机名——协议与路径对用户没有意义。 */
function hostOf(url: string): string {
  const scheme: number = url.indexOf('://')
  const rest: string = scheme < 0 ? url : url.substring(scheme + 3)
  const slash: number = rest.indexOf('/')
  return slash < 0 ? rest : rest.substring(0, slash)
}

/**
 * 设置。四组：影像（存相册）、归档目标（项目与云端用量）、账号（服务器、退出、注销）、关于。
 * 镜像安卓 `SettingsScreen.kt` 与 iOS `SettingsView`。
 */
@Component
export struct Settings {
  stack: NavPathStack = new NavPathStack()
  @State saveToAlbum: boolean = false
  @State projectName: string = DASH
  @State usage: MediaUsage | null = null
  private token: number = -1
  /** 这一屏还在不在。异步回调回来时组件可能已经销毁，往里写 @State 是错误日志甚至崩溃。 */
  private alive: boolean = false

  aboutToAppear(): void {
    this.alive = true
    this.token = AppModel.shared.subscribe((): void => this.syncProject())
    this.syncProject()
    ServiceLocator.prefs.saveToAlbum().then((v: boolean): void => {
      if (!this.alive) return
      this.saveToAlbum = v
    }).catch((): void => {})
    // 进页面拉一次用量。读不到就留占位「—」，比一条报错更符合这行信息的分量；
    // 但会话失效是另一回事——和选项目页同口径，回登录页，别让人对着一屏死数据点
    AppModel.shared.mediaUsage().then((u: MediaUsage): void => {
      if (!this.alive) return
      this.usage = u
    }).catch((e: Object): void => {
      if (e instanceof Unauthorized) {
        AppModel.shared.signOut().catch((): void => {})
        return
      }
      // 走查发现「—」常驻却查不出原因：其他失败也得留一行日志，不然无从定性
      hilog.warn(DOMAIN, TAG, 'mediaUsage failed: %{public}s', `${e}`)
    })
  }

  aboutToDisappear(): void {
    this.alive = false
    if (this.token >= 0) AppModel.shared.unsubscribe(this.token)
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar()
        Scroll() {
          Column() {
            this.mediaGroup()
            this.archiveGroup()
            this.accountGroup()
            this.aboutGroup()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: Tk.Sp.gutter, right: Tk.Sp.gutter, bottom: Tk.Sp.s16 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(Tk.L.bg)
  }

  @Builder
  topBar() {
    Column() {
      Row({ space: Tk.Sp.s2 }) {
        Text('✕')
          .fontSize(Tk.Ty.body)
          .fontColor(Tk.L.fg)
          .width(Tk.touchMin)
          .height(Tk.touchMin)
          .textAlign(TextAlign.Center)
          .accessibilityText(tr('common.close'))
          .onClick((): void => {
            this.stack.pop()
          })
        Text(tr('home.settings'))
          .fontSize(Tk.Ty.heading)
          .fontColor(Tk.L.fg)
      }
      .width('100%')
      .padding({ left: Tk.Sp.s2, right: Tk.Sp.gutter, bottom: Tk.Sp.s2 })

      Divider().color(Tk.L.rule)
    }
  }

  @Builder
  mediaGroup() {
    this.eyebrow(tr('settings.media'))
    Row({ space: Tk.Sp.s3 }) {
      Column({ space: Tk.Sp.s1 }) {
        Text(tr('settings.saveToAlbum'))
          .fontSize(Tk.Ty.body)
          .fontColor(Tk.L.fg)
        // 把权衡摆在这儿，让每次选择都是知情的
        Text(tr('settings.saveToAlbum.hint'))
          .fontSize(Tk.Ty.nano)
          .fontColor(Tk.L.fgFaint)
        // 鸿蒙没有静默写相册的路（spec H8）：开了之后每件都会弹系统确认，说在前面
        Text(tr('settings.saveToAlbum.dialogHint'))
          .fontSize(Tk.Ty.nano)
          .fontColor(Tk.L.fgFaint)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.saveToAlbum })
        .selectedColor(Tk.L.accent)
        .onChange((v: boolean): void => {
          this.saveToAlbum = v
          ServiceLocator.prefs.setSaveToAlbum(v).catch((): void => {})
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)

    this.rule()
  }

  @Builder
  archiveGroup() {
    this.eyebrow(tr('settings.archiveTarget'))
    this.infoRow(tr('home.eyebrow'), this.projectName)
    this.infoRow(tr('settings.relay'), this.usageCaption())
    Progress({ value: this.usageFraction(), total: 100, type: ProgressType.Linear })
      .color(Tk.L.accent)
      .backgroundColor(Tk.L.sunken)
      .width('100%')
    Text(tr('settings.switchProject'))
      .fontSize(Tk.Ty.small)
      .fontColor(Tk.L.accent)
      .height(Tk.touchMin)
      .onClick((): void => {
        this.stack.pushPath(new NavPathInfo('ProjectPickerSwitch', ''))
      })
    this.rule()
  }

  @Builder
  accountGroup() {
    this.eyebrow(tr('settings.account'))
    this.infoRow(tr('settings.signedIn'), this.accountName())
    this.infoRow(tr('settings.server'), hostOf(BASE_URL))
    Text(tr('common.signOut'))
      .fontSize(Tk.Ty.small)
      .fontColor(Tk.S.failed)
      .height(Tk.touchMin)
      .onClick((): void => {
        AppModel.shared.signOut().catch((): void => {})
      })
    // 放在退出登录下面、字号更小：它比退出重得多，不该长得一样容易误点
    Text(tr('settings.deleteAccount'))
      .fontSize(Tk.Ty.micro)
      .fontColor(Tk.L.fgMuted)
      .height(Tk.touchMin)
      .onClick((): void => this.confirmDelete())
    this.rule()
  }

  @Builder
  aboutGroup() {
    this.eyebrow(tr('settings.about'))
    this.infoRow(tr('settings.version'), ServiceLocator.facts.appVersion)
    this.infoRow(tr('settings.package'), ServiceLocator.ctx.applicationInfo.name)
    this.rule()
  }

  @Builder
  eyebrow(title: string) {
    Text(title)
      .fontSize(Tk.Ty.nano)
      .fontColor(Tk.L.fgMuted)
      .margin({ top: Tk.Sp.s6, bottom: Tk.Sp.s3 })
  }

  @Builder
  infoRow(key: string, value: string) {
    Column({ space: Tk.Sp.s1 }) {
      Text(key)
        .fontSize(Tk.Ty.small)
        .fontColor(Tk.L.fg)
      Text(value)
        .fontSize(Tk.Ty.nano)
        .fontColor(Tk.L.fgFaint)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: Tk.Sp.s3 })
  }

  @Builder
  rule() {
    Divider().color(Tk.L.rule).margin({ top: Tk.Sp.s2 })
  }

  // ---- 行为 ----

  /** 冷启动没有账号信息（会话里只有 sessionId），那就照实显示占位，不去多打一次网络。 */
  private accountName(): string {
    const a: AccountUser | null = AppModel.shared.account
    if (a === null) return DASH
    return a.displayName.length > 0 ? a.displayName : a.username
  }

  private syncProject(): void {
    const p: RelayProject | null = AppModel.shared.selectedProject
    this.projectName = p === null ? DASH : p.name
  }

  /** 「已用 / 配额」。满了之后上传会被拒并提示去桌面端收件，这行让用户提前有数。 */
  private usageCaption(): string {
    const u: MediaUsage | null = this.usage
    if (u === null) return DASH
    return tr('settings.usage', { 'used': formatBytes(u.usedBytes), 'quota': formatBytes(u.quotaBytes) })
  }

  private usageFraction(): number {
    const u: MediaUsage | null = this.usage
    if (u === null || u.quotaBytes <= 0) return 0
    const pct: number = (u.usedBytes / u.quotaBytes) * 100
    if (pct < 0) return 0
    return pct > 100 ? 100 : pct
  }

  /**
   * 不可逆，所以走二次确认；文案把「删什么、不删什么」都说全——
   * 只写「无法恢复」等于没说清代价。
   */
  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: tr('settings.deleteAccount.title'),
      message: tr('settings.deleteAccount.confirm'),
      autoCancel: true,
      primaryButton: {
        value: tr('common.cancel'),
        action: (): void => {},
      },
      secondaryButton: {
        value: tr('settings.deleteAccount'),
        fontColor: Tk.S.failed,
        action: (): void => {
          AppModel.shared.deleteAccount().catch((e: Object): void => {
            toast(this.getUIContext(), errorText(e))
          })
        },
      },
    })
  }
}
