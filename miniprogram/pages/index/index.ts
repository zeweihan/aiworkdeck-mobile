import { Icon } from '../../utils/icons'
import type { Metrics } from '../../utils/layout'
import type { GlassMode } from '../../utils/capability'

interface AppGlobal {
  globalData: { metrics: Metrics; glassMode: GlassMode }
}

/** 演示数据。接后端前用于视觉走查，接入时整块替换。 */
const DEMO = {
  project: { name: '华创科技 A 轮尽调', archivePath: '现场影像 / 2026-08-17' },
  desktop: { online: true, detail: '12 秒前同步 · MacBook Pro' },
  counts: { waiting: 12, moving: 3, arrived: 148 },
  recent: [
    { id: 1, kind: 'doc', state: 'arrived', time: '14:22' },
    { id: 2, kind: 'doc', state: 'arrived', time: '14:21' },
    { id: 3, kind: 'scene', state: 'moving', time: '14:19' },
    { id: 4, kind: 'doc', state: 'waiting', time: '14:18' },
    { id: 5, kind: 'scene', state: 'waiting', time: '14:16' },
    { id: 6, kind: 'doc', state: 'arrived', time: '14:11' },
  ],
}

Page({
  data: {
    Icon,
    metrics: {} as Metrics,
    glassMode: 'solid' as GlassMode,
    scrollTop: 0,
    ...DEMO,
  },

  onLoad() {
    const app = getApp<AppGlobal>()
    this.setData({
      metrics: app.globalData.metrics,
      glassMode: app.globalData.glassMode,
    })
  },

  onPageScroll(e: { scrollTop: number }) {
    // 只在跨过阈值时 setData，避免每帧都触发渲染层通信
    const crossed = e.scrollTop > 4
    if (crossed !== this.data.scrollTop > 4) {
      this.setData({ scrollTop: e.scrollTop })
    }
  },

  onCapture() {
    wx.vibrateShort({ type: 'light' })
    wx.showToast({ title: '拍摄页开发中', icon: 'none' })
  },

  onOpenQueue() {
    wx.navigateTo({ url: '/pages/queue/queue' })
  },

  onOpenFiles() {
    wx.showToast({ title: '文件页开发中', icon: 'none' })
  },

  onSwitchProject() {
    wx.showToast({ title: '项目切换开发中', icon: 'none' })
  },
})
