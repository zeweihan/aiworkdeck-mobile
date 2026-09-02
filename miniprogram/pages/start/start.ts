import { getSession, wxPhoneStart } from '../../utils/api'
import type { ApiError } from '../../utils/api'
import type { Metrics } from '../../utils/layout'
import { t } from '../../utils/i18n'

interface AppGlobal {
  globalData: { metrics: Metrics }
}

/**
 * 扫码引流落地页（dev-board#305）。
 *
 * 入口是官网 /start 微信内「微信一键开始」生成的 URL Link，不在 tabBar/主流程里。
 * 用户在这里点 getPhoneNumber 授权 → code 交官网换号建号（utils/api.ts
 * wxPhoneStart）→ 展示「账户已就绪 + 回电脑」，顺带介绍本小程序的现场伴侣
 * 功能（留存钩子）。不建小程序会话——插件云后端的会话仍走短信验证码登录。
 */

/** 回电脑的落点。展示用短写法，复制给的是带协议的完整地址。 */
const DESKTOP_URL_SHORT = 'aiworkdeck.com/start'
const DESKTOP_URL_FULL = 'https://aiworkdeck.com/zh/start'

Page({
  data: {
    metrics: {} as Metrics,
    desktopUrl: DESKTOP_URL_SHORT,
    working: false,
    done: false,
    error: '',
    displayName: '',
    isNewUser: false,
    // 与手机端上传时的文件名前缀共用同一份契约文案（dev-board#305 特性介绍卡片）
    featureAudioName: t('file.prefix.audio'),
  },

  /** 官网 CTA 透传的来源标记（u-<username>），原样交给换号端点记转化流水 */
  ref: '',

  onLoad(query: Record<string, string | undefined>) {
    const app = getApp<AppGlobal>()
    this.setData({ metrics: app.globalData.metrics })
    this.ref = typeof query.ref === 'string' ? query.ref : ''
  },

  onGetPhone(e: WechatMiniprogram.ButtonGetPhoneNumber) {
    const detail = e.detail || {}
    if (!detail.code) {
      // 用户在授权弹窗点了拒绝/取消：不是错误，轻声说一句还能再点即可
      const denied = (detail.errMsg || '').indexOf('deny') >= 0 || (detail.errMsg || '').indexOf('cancel') >= 0
      this.setData({
        error: denied
          ? '已取消。想继续的话再点一次按钮即可。'
          : '没有拿到手机号凭证，再点一次按钮试试。',
      })
      return
    }

    this.setData({ working: true, error: '' })
    wxPhoneStart(detail.code, this.ref)
      .then((result) => {
        this.setData({
          working: false,
          done: true,
          displayName: result.displayName,
          isNewUser: result.isNewUser,
        })
      })
      .catch((err: ApiError) => {
        this.setData({ working: false, error: err.message })
      })
  },

  onCopyUrl() {
    wx.setClipboardData({ data: DESKTOP_URL_FULL })
  },

  onEnterApp() {
    // 官网换号用的 ticket 不建小程序会话，这里没有会话是正常状态，
    // 直接去登录页（免得先弹一下 index 又被它的守门弹回来）。
    if (!getSession()) {
      wx.reLaunch({ url: '/pages/login/login' })
      return
    }
    // 有会话（比如之前登录过）：index 的 onShow 守门会按选中项目把用户送到该去的页面
    wx.reLaunch({ url: '/pages/index/index' })
  },
})
