import { getMetrics, metricsToStyle, type Metrics } from './utils/layout'
import { getGlassMode, type GlassMode } from './utils/capability'

interface GlobalData {
  metrics: Metrics
  metricsStyle: string
  glassMode: GlassMode
}

App<{ globalData: GlobalData }>({
  globalData: {} as GlobalData,

  onLaunch() {
    // 布局度量与渲染能力在启动时各算一次，全局复用。
    // 页面不许自己再调 getMenuButtonBoundingClientRect —— 那是顶部遮挡 bug 的来源。
    const metrics = getMetrics()
    this.globalData = {
      metrics,
      metricsStyle: metricsToStyle(metrics),
      glassMode: getGlassMode(),
    }
  },
})
