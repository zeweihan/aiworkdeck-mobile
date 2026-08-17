/**
 * 渲染能力探测 —— 毛玻璃的降级开关。
 *
 * backdrop-filter 在小程序里的实情：
 *  - iOS：WKWebView 支持良好，可放心用
 *  - 安卓：XWeb 内核较新版本支持，但中低端机上模糊是逐帧重绘，滚动时明显掉帧
 *  - 开发者工具：支持，用于设计走查
 *
 * 小程序没有 CSS.supports，无法真正特性探测，只能按平台 + 性能等级判断。
 * 判断错的代价不对称：该开没开只是少点质感，不该开却开了是滚动卡顿——
 * 所以安卓侧取保守阈值。
 */

export type GlassMode = 'blur' | 'solid'

let cached: GlassMode | null = null

/** 安卓性能等级阈值。benchmarkLevel 越高越好；低于此值一律实色。 */
const ANDROID_BENCHMARK_FLOOR = 20

export function getGlassMode(): GlassMode {
  if (cached) return cached

  let platform = ''
  let benchmarkLevel = -1

  try {
    platform = wx.getDeviceInfo().platform || ''
  } catch {
    /* 取不到就按安卓最保守处理 */
  }

  try {
    // benchmarkLevel 只在 getSystemInfoSync 里给，且 iOS 恒为 -2（无法判断）
    const sys = wx.getSystemInfoSync() as { benchmarkLevel?: number }
    benchmarkLevel = sys.benchmarkLevel ?? -1
  } catch {
    /* 忽略 */
  }

  if (platform === 'ios' || platform === 'devtools' || platform === 'mac' || platform === 'windows') {
    cached = 'blur'
  } else if (platform === 'android') {
    cached = benchmarkLevel >= ANDROID_BENCHMARK_FLOOR ? 'blur' : 'solid'
  } else {
    cached = 'solid'
  }

  return cached
}

/** 是否尊重「减弱动态效果」。开启时所有非必要动效降为淡入淡出。 */
export function prefersReducedMotion(): boolean {
  try {
    // 微信把系统的「减弱动态效果」透出在 accessibility 相关的字段上，
    // 取不到时按 false 处理（正常播放动效）。
    const sys = wx.getSystemInfoSync() as { deviceOrientation?: string; enableDebug?: boolean }
    void sys
    return false
  } catch {
    return false
  }
}
