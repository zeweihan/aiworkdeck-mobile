import type { Metrics } from '../../utils/layout'
import { t } from '../../utils/i18n'

interface AppGlobal {
  globalData: { metrics: Metrics }
}

/**
 * 下载 App 页（dev-board#839）。从登录页选「海外版」后进来：小程序登不了海外版账号，
 * 引导用户去装原生 App。小程序打不开 App Store 链接，所以 iOS 给「复制链接」；
 * 安卓、鸿蒙尚未上架，只标「即将上线」。
 */

/** 中国区 App Store 的 AI WorkDeck 页面（已实测可打开）。是地址不是界面文案，不进词典。 */
const APP_STORE_URL = 'https://apps.apple.com/cn/app/id6803309103'

/** 页面文案。Page({ data }) 在小程序启动注册时就求值了（那时一定是中文），
 *  所以要在 onLoad 按当前语言（登录页选海外版时是 en）再取一遍。 */
function boundTexts() {
  return {
    navTitle: t('download.title'),
    iosLabel: t('download.ios'),
    iosHint: t('download.ios.hint'),
    iosCopyText: t('download.ios.copy'),
    androidLabel: t('download.android'),
    harmonyLabel: t('download.harmony'),
    comingSoonText: t('download.comingSoon'),
  }
}

Page({
  data: {
    metrics: {} as Metrics,
    ...boundTexts(),
  },

  onLoad() {
    const app = getApp<AppGlobal>()
    this.setData({ metrics: app.globalData.metrics, ...boundTexts() })
  },

  onCopyIos() {
    wx.setClipboardData({
      data: APP_STORE_URL,
      success: () => {
        // setClipboardData 自带一个「内容已复制」提示，这里用契约文案覆盖它
        wx.showToast({ icon: 'none', title: t('download.copied') })
      },
    })
  },
})
