import { hilog } from '@kit.PerformanceAnalysisKit'
import { ContractCapabilities } from 'contract'
import { AppModel } from '../AppModel'
import { Pill, PrimaryButton, SegmentToggle } from '../design/Components'
import { LOCALE_ZH, trIn } from '../design/L10n'
import { Tk } from '../design/Tokens'
import { LoginResult } from '../services/ApiTypes'
import {
  AccountRegion, LoginMethod, defaultLoginMethodOf, loginMethodsOf,
} from '../model/AccountRegion'
import { ServiceLocator } from '../services/ServiceLocator'
import { errorText, toast } from './Feedback'

enum Step { identity = 'identity', code = 'code' }

const CODE_LENGTH: number = 6
const PHONE_LENGTH: number = 11
const RESEND_SECONDS: number = 60
const DOMAIN: number = 0x0000
const TAG: string = 'Login'

function digitsOnly(s: string): string {
  let out: string = ''
  for (const ch of s) {
    if (ch >= '0' && ch <= '9') out += ch
  }
  return out
}

/** 只做「明显不是邮箱」的拦截，不做 RFC 校验——真正的判定在后端，客户端把合法地址挡下来更糟。 */
export function looksLikeEmail(email: string): boolean {
  const at: number = email.indexOf('@')
  if (at <= 0) return false
  const domain: string = email.substring(at + 1)
  return domain.includes('.') && !domain.startsWith('.') && !domain.endsWith('.')
}

/** 回显发到哪去了，但不把标识完整重复一遍——旁边有人时那是一次不必要的泄露。 */
function mask(method: LoginMethod, value: string): string {
  if (method === LoginMethod.phone) {
    return value.length < 7 ? value : `${value.substring(0, 3)}****${value.substring(value.length - 4)}`
  }
  const at: number = value.indexOf('@')
  if (at < 0) return value
  const name: string = value.substring(0, at)
  const head: string = name.length <= 1 ? '***' : `${name.substring(0, 1)}***`
  return head + value.substring(at)
}

/**
 * 首屏登录：手机号或邮箱 + 验证码。镜像安卓 `LoginScreen.kt` 与 iOS `LoginView`。
 *
 * 两条路径语义相同（注册与登录合一，号码/地址没见过后端就建号），差别只在通道：
 * 短信只走中国大陆。鸿蒙只发大陆（spec H3），所以默认短信，邮箱留着给带境外号的人。
 *
 * 顶部的账号区域切换（dev-board#837）：大陆站与国际站是两套账号。国际站没有短信通道，
 * 选国际时只剩邮箱。区域只在这一屏能改，登录后固定。
 */
@Component
export struct Login {
  /** 界面语言的可观察副本：换区时 ServiceLocator 改写它，经 t() 用到文案的控件当场重绘。 */
  @StorageProp('awdLocale') locale: string = LOCALE_ZH
  @State region: AccountRegion = ServiceLocator.region
  @State method: LoginMethod = defaultLoginMethodOf(ServiceLocator.region)
  @State step: Step = Step.identity
  @State phone: string = ''
  @State email: string = ''
  @State code: string = ''
  @State busy: boolean = false
  @State cooldown: number = 0
  private tickId: number = -1

  aboutToDisappear(): void {
    this.stopCooldown()
  }

  build() {
    NavDestination() {
      Column() {
        if (ContractCapabilities.intlAccount) {
          this.regionToggle()
        }
        Blank()
        this.header()
        if (this.step === Step.identity && loginMethodsOf(this.region).length > 1) {
          Row({ space: Tk.Sp.s2 }) {
            Pill({
              label: this.t('login.phone'), selected: this.method === LoginMethod.phone,
              onTap: (): void => this.pick(LoginMethod.phone),
            })
            Pill({
              label: this.t('login.email'), selected: this.method === LoginMethod.email,
              onTap: (): void => this.pick(LoginMethod.email),
            })
          }
          .margin({ top: Tk.Sp.s4 })
        }
        this.field()
        Divider().color(Tk.L.rule).margin({ top: Tk.Sp.s3 })
        PrimaryButton({
          label: this.step === Step.identity ? this.t('login.sendCode') : this.t('login.title'),
          isEnabled: this.canSubmit() && !this.busy,
          onTap: (): void => this.submit(),
        })
          .margin({ top: Tk.Sp.s6 })
        if (this.step === Step.code) {
          this.codeActions()
        }
        Blank()
        Divider().color(Tk.L.rule)
        Text(this.t('login.help'))
          .fontSize(Tk.Ty.nano)
          .fontColor(Tk.L.fgFaint)
          .margin({ top: Tk.Sp.s3, bottom: Tk.Sp.s6 })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Tk.Sp.gutter, right: Tk.Sp.gutter })
    }
    .hideTitleBar(true)
    .backgroundColor(Tk.L.bg)
  }

  /** 右上角的区域开关：一个胶囊、点一下翻到另一边（见 SegmentToggle）。 */
  @Builder
  regionToggle() {
    Row() {
      Blank()
      SegmentToggle({
        leftLabel: this.t('login.region.cn'),
        rightLabel: this.t('login.region.intl'),
        rightOn: this.region === AccountRegion.intl,
        a11yLabel: this.t('login.region.a11y'),
        onToggle: (): void => this.switchRegion(
          this.region === AccountRegion.intl ? AccountRegion.cn : AccountRegion.intl),
      })
    }
    .width('100%')
    .margin({ top: Tk.Sp.s2 })
  }

  @Builder
  header() {
    Column({ space: Tk.Sp.s1 }) {
      Text(this.step === Step.identity ? this.t('login.title') : this.t('login.codeTitle'))
        .fontSize(Tk.Ty.nano)
        .fontColor(Tk.L.fgMuted)
      Text(this.title())
        .fontSize(Tk.Ty.display)
        .fontColor(Tk.L.fg)
      if (this.step === Step.identity && this.region === AccountRegion.intl) {
        Text(this.t('login.region.intlHint'))
          .fontSize(Tk.Ty.micro)
          .fontColor(Tk.L.fgFaint)
      }
      if (this.step === Step.code) {
        Text(this.t('login.sentTo', { 'to': mask(this.method, this.identity()) }))
          .fontSize(Tk.Ty.micro)
          .fontColor(Tk.L.fgFaint)
      }
    }
    .alignItems(HorizontalAlign.Start)
  }

  /** 输入框：一格大号，看得清、核得准。手机号只收数字、验证码只收 6 位并满位自动提交。 */
  @Builder
  field() {
    Column() {
      if (this.step === Step.code) {
        TextInput({ text: this.code, placeholder: '······' })
          .type(InputType.Number)
          .maxLength(CODE_LENGTH)
          .fontSize(Tk.Ty.hero / 2)
          .fontColor(Tk.L.fg)
          .caretColor(Tk.L.accent)
          .backgroundColor(Tk.L.bg)
          .padding(0)
          .onChange((v: string): void => this.onCode(v))
      } else if (this.method === LoginMethod.phone) {
        TextInput({ text: this.phone, placeholder: this.t('login.phonePlaceholder') })
          .type(InputType.PhoneNumber)
          .maxLength(PHONE_LENGTH)
          .fontSize(Tk.Ty.title)
          .fontColor(Tk.L.fg)
          .caretColor(Tk.L.accent)
          .backgroundColor(Tk.L.bg)
          .padding(0)
          .onChange((v: string): void => {
            this.phone = digitsOnly(v).substring(0, PHONE_LENGTH)
          })
      } else {
        TextInput({ text: this.email, placeholder: this.t('login.emailPlaceholder') })
          .type(InputType.Email)
          .fontSize(Tk.Ty.title)
          .fontColor(Tk.L.fg)
          .caretColor(Tk.L.accent)
          .backgroundColor(Tk.L.bg)
          .padding(0)
          .onChange((v: string): void => {
            this.email = v.trim()
          })
      }
    }
    .width('100%')
    .margin({ top: this.step === Step.identity ? Tk.Sp.s5 : Tk.Sp.s8 })
  }

  @Builder
  codeActions() {
    Row({ space: Tk.Sp.s5 }) {
      Text(this.cooldown > 0 ? this.t('login.resendIn', { 's': this.cooldown }) : this.t('login.resend'))
        .fontSize(Tk.Ty.small)
        .fontColor(this.cooldown > 0 || this.busy ? Tk.L.fgFaint : Tk.L.accent)
        .onClick((): void => {
          if (this.cooldown === 0 && !this.busy) this.send()
        })
      Text(this.method === LoginMethod.phone ? this.t('login.changePhone') : this.t('login.changeEmail'))
        .fontSize(Tk.Ty.small)
        .fontColor(Tk.L.fgMuted)
        .onClick((): void => {
          this.step = Step.identity
          this.code = ''
        })
    }
    .height(Tk.touchMin)
    .margin({ top: Tk.Sp.s4 })
  }

  // ---- 行为 ----

  /** 按本页订阅的语言取文案——读 this.locale 就是让 ArkUI 记下依赖，语言一变跟着重绘。 */
  private t(key: string, vars?: Record<string, string | number>): string {
    return trIn(this.locale, key, vars)
  }

  private title(): string {
    if (this.step === Step.code) return this.t('login.codePrompt')
    return this.method === LoginMethod.phone ? this.t('login.phone') : this.t('login.email')
  }

  private identity(): string {
    return this.method === LoginMethod.phone ? this.phone : this.email
  }

  private canSubmit(): boolean {
    if (this.step === Step.code) return this.code.length === CODE_LENGTH
    if (this.method === LoginMethod.phone) return this.phone.length === PHONE_LENGTH
    return looksLikeEmail(this.email)
  }

  /** 切换要清掉验证码，否则会出现「填了邮箱、报的是手机号那条的错」这种对不上号的状态。 */
  private pick(m: LoginMethod): void {
    if (this.method === m) return
    this.method = m
    this.code = ''
  }

  /**
   * 换区：回到填标识那一步，清空输入与冷却——上一个站的号码、验证码拿到另一个站没有意义。
   * 请求在途时不让切：发码/校验的结果回来时已经对不上当前区域了。
   */
  private switchRegion(r: AccountRegion): void {
    if (this.region === r || this.busy) return
    this.region = r
    this.method = defaultLoginMethodOf(r)
    this.step = Step.identity
    this.phone = ''
    this.email = ''
    this.code = ''
    this.stopCooldown()
    ServiceLocator.setRegion(r).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'setRegion persist failed: %{public}s', `${e}`)
    })
  }

  private onCode(v: string): void {
    this.code = digitsOnly(v).substring(0, CODE_LENGTH)
    if (this.code.length === CODE_LENGTH) this.verify()
  }

  private submit(): void {
    if (!this.canSubmit() || this.busy) return
    if (this.step === Step.identity) this.send()
    else this.verify()
  }

  private send(): void {
    if (this.busy) return
    this.busy = true
    this.sendAsync().then((): void => {
      this.busy = false
    }).catch((e: Object): void => {
      this.busy = false
      toast(this.getUIContext(), errorText(e))
    })
  }

  private async sendAsync(): Promise<void> {
    if (this.method === LoginMethod.phone) await ServiceLocator.backend.sendLoginCode(this.phone)
    else await ServiceLocator.backend.sendMailLoginCode(this.email)
    this.step = Step.code
    this.code = ''
    this.startCooldown()
  }

  private verify(): void {
    if (this.busy) return
    this.busy = true
    this.verifyAsync().then((): void => {
      this.busy = false
    }).catch((e: Object): void => {
      this.busy = false
      this.code = ''
      toast(this.getUIContext(), errorText(e))
    })
  }

  private async verifyAsync(): Promise<void> {
    const result: LoginResult = this.method === LoginMethod.phone
      ? await ServiceLocator.backend.verifyLoginCode(this.phone, this.code)
      : await ServiceLocator.backend.verifyMailLoginCode(this.email, this.code)
    this.stopCooldown()
    // 选过项目的直接回取景器，没选过的进选择页——这一步由 AppModel 决定，登录页不判断
    await AppModel.shared.didLogin(result.user)
  }

  /** 60 秒重发冷却。后端也有冷却，这里只是别让人白点。 */
  private startCooldown(): void {
    this.stopCooldown()
    this.cooldown = RESEND_SECONDS
    this.tickId = setInterval((): void => {
      this.cooldown = this.cooldown - 1
      if (this.cooldown <= 0) this.stopCooldown()
    }, 1000)
  }

  private stopCooldown(): void {
    if (this.tickId >= 0) {
      clearInterval(this.tickId)
      this.tickId = -1
    }
    this.cooldown = 0
  }
}
