import type { Metrics } from '../../utils/layout'
import type { GlassMode } from '../../utils/capability'

interface AppGlobal {
  globalData: { metrics: Metrics; glassMode: GlassMode }
}

Component({
  options: { multipleSlots: true },

  properties: {
    title: { type: String, value: '' },
    subtitle: { type: String, value: '' },
    showBack: { type: Boolean, value: false },
    /** 页面滚动距离，由页面透传。超过阈值才显示底部分隔线。 */
    scrollTop: { type: Number, value: 0 },
  },

  data: {
    metrics: {} as Metrics,
    glassMode: 'solid' as GlassMode,
    scrolled: false,
  },

  observers: {
    scrollTop(v: number) {
      const next = v > 4
      if (next !== this.data.scrolled) this.setData({ scrolled: next })
    },
  },

  lifetimes: {
    attached() {
      const app = getApp<AppGlobal>()
      this.setData({
        metrics: app.globalData.metrics,
        glassMode: app.globalData.glassMode,
      })
    },
  },

  methods: {
    onBack() {
      wx.navigateBack({ delta: 1 })
    },
    onTitleTap() {
      this.triggerEvent('titletap')
    },
  },
})
