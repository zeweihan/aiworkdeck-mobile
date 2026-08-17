/** 视觉走查用演示数据。接后端时整块删除。 */

export const PROJECT = { name: '华创科技 A 轮尽调', archive: '现场影像 / 2026-08-17' }

export const STATS = [
  { key: 'waiting', n: 12, name: '待传输', where: '在手机上' },
  { key: 'moving', n: 3, name: '传输中', where: '在路上' },
  { key: 'arrived', n: 148, name: '已归档', where: '现场影像 / 08-17' },
]

export const RECENT = [
  { id: 1, kind: 'doc', state: 'arrived', time: '14:22' },
  { id: 2, kind: 'doc', state: 'arrived', time: '14:21' },
  { id: 3, kind: 'scene', state: 'moving', time: '14:19' },
  { id: 4, kind: 'doc', state: 'waiting', time: '14:18' },
  { id: 5, kind: 'scene', state: 'waiting', time: '14:16' },
  { id: 6, kind: 'doc', state: 'arrived', time: '14:11' },
  { id: 7, kind: 'scene', state: 'arrived', time: '14:04' },
  { id: 8, kind: 'doc', state: 'arrived', time: '13:58' },
]

interface Metrics {
  navTotalHeight: number
  statusBarHeight: number
  navContentHeight: number
  capsuleRightInset: number
  bottomInset: number
}

/** 三个方案页共用的最小 Page 定义。 */
export function variantPage(extra: Record<string, unknown> = {}) {
  return {
    data: {
      m: {} as Metrics,
      project: PROJECT,
      stats: STATS,
      recent: RECENT,
      ...extra,
    },
    onLoad(this: WechatMiniprogram.Page.Instance<Record<string, unknown>, Record<string, unknown>>) {
      const app = getApp<{ globalData: { metrics: Metrics } }>()
      this.setData({ m: app.globalData.metrics })
    },
    onCapture() {
      wx.vibrateShort({ type: 'light' })
      wx.showToast({ title: '拍摄页开发中', icon: 'none' })
    },
  }
}
