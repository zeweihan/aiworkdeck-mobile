import { AppModel } from '../AppModel'
import { Pill, PrimaryButton } from '../design/Components'
import { tr } from '../design/L10n'
import { Tk } from '../design/Tokens'
import { LoginResult } from '../services/ApiTypes'
import { ServiceLocator } from '../services/ServiceLocator'
import { errorText, toast } from './Feedback'

enum Method { phone = 'phone', email = 'email' }

enum Step { identity = 'identity', code = 'code' }

const CODE_LENGTH: number = 6
const PHONE_LENGTH: number = 11
const RESEND_SECONDS: number = 60

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
function mask(method: Method, value: string): string {
  if (method === Method.phone) {
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
 */
@Component
export struct Login {
  @State method: Method = Method.phone
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
        Blank()
        this.header()
        if (this.step === Step.identity) {
          Row({ space: Tk.Sp.s2 }) {
            Pill({
              label: tr('login.phone'), selected: this.method === Method.phone,
              onTap: (): void => this.pick(Method.phone),
            })
            Pill({
              label: tr('login.email'), selected: this.method === Method.email,
              onTap: (): void => this.pick(Method.email),
            })
          }
          .margin({ top: Tk.Sp.s4 })
        }
        this.field()
        Divider().color(Tk.L.rule).margin({ top: Tk.Sp.s3 })
        PrimaryButton({
          label: this.step === Step.identity ? tr('login.sendCode') : tr('login.title'),
          isEnabled: this.canSubmit() && !this.busy,
          onTap: (): void => this.submit(),
        })
          .margin({ top: Tk.Sp.s6 })
        if (this.step === Step.code) {
          this.codeActions()
        }
        Blank()
        Divider().color(Tk.L.rule)
        Text(tr('login.help'))
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

  @Builder
  header() {
    Column({ space: Tk.Sp.s1 }) {
      Text(this.step === Step.identity ? tr('login.title') : tr('login.codeTitle'))
        .fontSize(Tk.Ty.nano)
        .fontColor(Tk.L.fgMuted)
      Text(this.title())
        .fontSize(Tk.Ty.display)
        .fontColor(Tk.L.fg)
      if (this.step === Step.code) {
        Text(tr('login.sentTo', { 'to': mask(this.method, this.identity()) }))
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
      } else if (this.method === Method.phone) {
        TextInput({ text: this.phone, placeholder: tr('login.phonePlaceholder') })
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
        TextInput({ text: this.email, placeholder: tr('login.emailPlaceholder') })
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
      Text(this.cooldown > 0 ? tr('login.resendIn', { 's': this.cooldown }) : tr('login.resend'))
        .fontSize(Tk.Ty.small)
        .fontColor(this.cooldown > 0 || this.busy ? Tk.L.fgFaint : Tk.L.accent)
        .onClick((): void => {
          if (this.cooldown === 0 && !this.busy) this.send()
        })
      Text(this.method === Method.phone ? tr('login.changePhone') : tr('login.changeEmail'))
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

  private title(): string {
    if (this.step === Step.code) return tr('login.codePrompt')
    return this.method === Method.phone ? tr('login.phone') : tr('login.email')
  }

  private identity(): string {
    return this.method === Method.phone ? this.phone : this.email
  }

  private canSubmit(): boolean {
    if (this.step === Step.code) return this.code.length === CODE_LENGTH
    if (this.method === Method.phone) return this.phone.length === PHONE_LENGTH
    return looksLikeEmail(this.email)
  }

  /** 切换要清掉验证码，否则会出现「填了邮箱、报的是手机号那条的错」这种对不上号的状态。 */
  private pick(m: Method): void {
    if (this.method === m) return
    this.method = m
    this.code = ''
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
    if (this.method === Method.phone) await ServiceLocator.backend.sendLoginCode(this.phone)
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
    const result: LoginResult = this.method === Method.phone
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
