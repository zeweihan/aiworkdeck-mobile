import { sendLoginCode, verifyLoginCode } from '../../utils/api'
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
