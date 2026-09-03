import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppModel, Route } from '../AppModel'
import { tr } from '../design/L10n'
import { Tk } from '../design/Tokens'
import { RelayProject } from '../model/Capture'
import { Login } from './Login'
import { ProjectPicker } from './ProjectPicker'
import { Settings } from './Settings'

const DOMAIN: number = 0x0000
const TAG: string = 'Root'

const PAGE_LOGIN: string = 'Login'
const PAGE_PROJECTS: string = 'ProjectPicker'
/** 换项目：从设置页进来的那一次，选完退回设置而不是推去取景器。 */
const PAGE_PROJECTS_SWITCH: string = 'ProjectPickerSwitch'
const PAGE_HOME: string = 'Home'
const PAGE_SETTINGS: string = 'Settings'

/**
 * 根路由。四态互斥、按顺序判定：还没恢复完（boot）→ 没登录 → 没选项目 → 主界面，
 * 与安卓 `MainActivity.Root` 一致，只是换成 Navigation 栈来承载。
 *
 * 路由由 AppModel 的 `route` 说了算，这里只负责把它翻译成栈操作：
 * 每次换态先 `clear()` 再 `pushPath()`——这四态之间没有「返回上一态」的语义
 * （登出之后能按返回键回到取景器是安全事故），所以不留历史。
 */
@Entry
@Component
struct Root {
  private readonly stack: NavPathStack = new NavPathStack()
  @State @Watch('applyRoute') route: Route = Route.boot
  private token: number = -1

  aboutToAppear(): void {
    this.token = AppModel.shared.subscribe((): void => {
      const r: Route = AppModel.shared.route
      if (this.route !== r) this.route = r
    })
    AppModel.shared.bootstrap().catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, 'bootstrap failed: %{public}s', `${e}`)
    })
  }

  aboutToDisappear(): void {
    if (this.token >= 0) AppModel.shared.unsubscribe(this.token)
  }

  applyRoute(): void {
    this.stack.clear(false)
    if (this.route === Route.login) this.stack.pushPath(new NavPathInfo(PAGE_LOGIN, ''), false)
    else if (this.route === Route.projects) this.stack.pushPath(new NavPathInfo(PAGE_PROJECTS, ''), false)
    else if (this.route === Route.home) this.stack.pushPath(new NavPathInfo(PAGE_HOME, ''), false)
    // boot：什么都不推，露出 Navigation 自己那张与主界面同色的空屏
  }

  @Builder
  pageMap(name: string) {
    if (name === PAGE_LOGIN) {
      Login()
    } else if (name === PAGE_PROJECTS) {
      ProjectPicker({ stack: this.stack, switching: false })
    } else if (name === PAGE_PROJECTS_SWITCH) {
      ProjectPicker({ stack: this.stack, switching: true })
    } else if (name === PAGE_SETTINGS) {
      Settings({ stack: this.stack })
    } else {
      HomeStub({ stack: this.stack })
    }
  }

  build() {
    Navigation(this.stack) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Tk.L.bg)
    }
    .hideTitleBar(true)
    .navDestination(this.pageMap)
    .width('100%')
    .height('100%')
    .backgroundColor(Tk.L.bg)
  }
}

/**
 * 取景首页的占位。Task 6 用真正的取景器（相机预览 + 三档 + 水印）整个换掉这一屏，
 * 这里只留两条出口，好让登录 → 选项目 → 设置 → 退出这条链在模拟器上能走通。
 */
@Component
struct HomeStub {
  stack: NavPathStack = new NavPathStack()
  @State projectName: string = ''
  private token: number = -1

  aboutToAppear(): void {
    this.token = AppModel.shared.subscribe((): void => this.sync())
    this.sync()
  }

  aboutToDisappear(): void {
    if (this.token >= 0) AppModel.shared.unsubscribe(this.token)
  }

  build() {
    NavDestination() {
      Column({ space: Tk.Sp.s4 }) {
        Text(tr('home.eyebrow'))
          .fontSize(Tk.Ty.nano)
          .fontColor(Tk.L.fgMuted)
        Text(this.projectName)
          .fontSize(Tk.Ty.display)
          .fontColor(Tk.L.fg)
        Text(tr('home.settings'))
          .fontSize(Tk.Ty.small)
          .fontColor(Tk.L.accent)
          .height(Tk.touchMin)
          .onClick((): void => {
            this.stack.pushPath(new NavPathInfo(PAGE_SETTINGS, ''))
          })
        Text(tr('common.signOut'))
          .fontSize(Tk.Ty.small)
          .fontColor(Tk.L.fgMuted)
          .height(Tk.touchMin)
          .onClick((): void => {
            AppModel.shared.signOut().catch((): void => {})
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .hideTitleBar(true)
    .backgroundColor(Tk.L.bg)
  }

  private sync(): void {
    const p: RelayProject | null = AppModel.shared.selectedProject
    this.projectName = p === null ? '' : p.name
  }
}
