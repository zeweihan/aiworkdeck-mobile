import { sendLoginCode, verifyLoginCode, wxPhoneLogin } from '../../utils/api'
import type { ApiError } from '../../utils/api'
import type { Metrics } from '../../utils/layout'
import { t } from '../../utils/i18n'

interface AppGlobal {
  globalData: { metrics: Metrics }
}

const COUNTDOWN_SECONDS = 60

Page({
  data: {
    metrics: {} as Metrics,
    phone: '',
    code: '',
    sendingCode: false,
    loggingIn: false,
    countdown: 0,
    navTitle: t('login.title'),
    phoneLabel: t('login.phone'),
    codeLabel: t('login.codeTitle'),
    submitText: t('login.title'),
    codeButtonText: t('login.sendCode'),
    sendDisabled: true,
    submitDisabled: true,
    /** 一键登录是首屏；短信表单默认折叠，用户点开或一键登录走不通时才展开 */
    smsOpen: false,
    wxLoggingIn: false,
    wxPhoneText: t('login.wxPhone'),
    useSmsText: t('login.useSms'),
  },

  timer: null as ReturnType<typeof setInterval> | null,

  onLoad() {
    const app = getApp<AppGlobal>()
    this.setData({ metrics: app.globalData.metrics })
  },

  onUnload() {
    if (this.timer) clearInterval(this.timer)
  },

  /** 手机号 / 验证码 / 倒计时 / 请求中任一变化后，统一重算两个按钮的态。 */
  refreshButtons() {
    const { phone, code, sendingCode, loggingIn, countdown } = this.data
    const phoneValid = phone.length === 11
    const codeValid = code.length === 6
    this.setData({
      sendDisabled: !phoneValid || sendingCode || countdown > 0,
      submitDisabled: !phoneValid || !codeValid || loggingIn,
      codeButtonText: sendingCode
        ? '发送中…'
        : countdown > 0
          ? `${countdown}s 后重新获取`
          : t('login.sendCode'),
    })
  },

  onOpenSms() {
    this.setData({ smsOpen: true })
  },

  /**
   * 微信手机号一键登录（dev-board#534，规格 docs/specs/2026-09-09-miniprogram-entry-and-wx-login.md §2）。
   *
   * 三条分支，缺一不可：
   *  - 用户点了拒绝：**不报错**，只把短信表单展开——拒绝授权是正常选择，不是故障；
   *  - 拿到 code 但服务端不给过（本服务器没开通 / 授权过期 / 非大陆号，一律 code 1）：
   *    toast 服务端的 message 并展开短信表单；
   *  - 成功：与 verifyLoginCode 同一条路（会话已在 api 层存好），进项目页。
   */
  onGetPhone(e: WechatMiniprogram.ButtonGetPhoneNumber) {
    const detail = e.detail || {}
    if (!detail.code) {
      // 拒绝授权 / 取消 / 没拿到凭证：都不弹错误，把短信表单展开就是最直接的下一步
      this.setData({ smsOpen: true })
      return
    }

    this.setData({ wxLoggingIn: true })
    wxPhoneLogin(detail.code)
      .then(() => {
        wx.reLaunch({ url: '/pages/project/project' })
      })
      .catch((err: ApiError) => {
        this.setData({ wxLoggingIn: false, smsOpen: true })
        wx.showToast({ icon: 'none', title: err.message })
      })
  },

  onPhoneInput(e: { detail: { value: string } }) {
    this.setData({ phone: e.detail.value.slice(0, 11) }, () => this.refreshButtons())
  },

  onCodeInput(e: { detail: { value: string } }) {
    this.setData({ code: e.detail.value.slice(0, 6) }, () => this.refreshButtons())
  },

  onSendCode() {
    if (this.data.sendDisabled) return
    this.setData({ sendingCode: true }, () => this.refreshButtons())
    sendLoginCode(this.data.phone)
      .then(() => {
        this.setData({ sendingCode: false, countdown: COUNTDOWN_SECONDS }, () => {
          this.refreshButtons()
          this.startCountdown()
        })
      })
      .catch((err: ApiError) => {
        this.setData({ sendingCode: false }, () => this.refreshButtons())
        wx.showToast({ icon: 'none', title: err.message })
      })
  },

  startCountdown() {
    if (this.timer) clearInterval(this.timer)
    this.timer = setInterval(() => {
      const next = this.data.countdown - 1
      if (next <= 0) {
        if (this.timer) clearInterval(this.timer)
        this.timer = null
        this.setData({ countdown: 0 }, () => this.refreshButtons())
      } else {
        this.setData({ countdown: next }, () => this.refreshButtons())
      }
    }, 1000)
  },

  onLogin() {
    if (this.data.submitDisabled) return
    this.setData({ loggingIn: true }, () => this.refreshButtons())
    verifyLoginCode(this.data.phone, this.data.code)
      .then(() => {
        wx.reLaunch({ url: '/pages/project/project' })
      })
      .catch((err: ApiError) => {
        this.setData({ loggingIn: false }, () => this.refreshButtons())
        wx.showToast({ icon: 'none', title: err.message })
      })
  },
})
