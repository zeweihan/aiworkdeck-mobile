import { Icon } from '../../utils/icons'
import type { Metrics } from '../../utils/layout'
import { listItems, subscribe, pollStatus, retry, type QueueItem, type QueueState } from '../../utils/queue'
import { thumbFor, markThumbBroken } from '../../utils/thumbs'

interface AppGlobal {
  globalData: { metrics: Metrics }
}

/** 队列轮询节奏：5 秒一次，见实施契约 §3 */
const POLL_INTERVAL = 5000

/** 一条队列记录在页面上展示用的精简结构 */
interface DisplayItem {
  clientMediaId: string
  /** 真实缩略图路径（照片原图 / 录像帧图），空串走占位色块 + 图标 */
  thumb: string
  /** 占位色块的媒体类别（沿用 doc/scene/audio 的既有配色） */
  kind: 'doc' | 'scene' | 'audio'
  kindIcon: string
  fileName: string
  time: string
  projectName: string
  statusText: string
  waitingText: string
  /** failed 态的服务端/网络层可读错误原文（如「云端空间已满」），空串不渲染 */
  errorText: string
  /** 快到期的黄字提醒，空串不渲染 */
  expiresText: string
  dotClass: string
  canRetry: boolean
}

function formatTime(ts: number): string {
  const d = new Date(ts)
  const hh = `${d.getHours()}`.padStart(2, '0')
  const mm = `${d.getMinutes()}`.padStart(2, '0')
  return `${hh}:${mm}`
}

function statusText(state: QueueState): string {
  switch (state) {
    case 'waiting':
      return '待上传'
    case 'uploading':
      return '上传中'
    case 'failed':
      return '上传失败'
    case 'uploaded':
      return '已上传 · 等待桌面端接收'
    case 'arrived':
      return '已抵达'
  }
}

/** 桌面端离线不可隐瞒：uploaded 态等待超过 60 秒要明说等了多久 */
function waitingText(item: QueueItem): string {
  if (item.state !== 'uploaded') return ''
  const seconds = item.waitingSeconds ?? 0
  if (seconds < 60) return ''
  return `已等待 ${Math.floor(seconds / 60)} 分钟`
}

/** iOS 的 JSC 解析不带时区的 ISO 字符串不可靠，手工拆字段按本地时间构造 */
function parseLocalIso(s: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/.exec(s)
  if (!m) return null
  return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || '0')).getTime()
}

/** 已上传未抵达且剩余保存期不足 3 天：黄字催收，过期即删不可隐瞒 */
function expiresText(item: QueueItem): string {
  if (item.state !== 'uploaded' || !item.expiresAt) return ''
  const ts = parseLocalIso(item.expiresAt)
  if (ts === null) return ''
  if (ts - Date.now() >= 3 * 24 * 3600 * 1000) return ''
  const d = new Date(ts)
  return `云端保存至 ${d.getMonth() + 1}月${d.getDate()}日，请尽快在桌面端接收`
}

function dotClass(state: QueueState): string {
  if (state === 'failed') return 'dot--failed'
  if (state === 'waiting') return 'dot--waiting'
  if (state === 'arrived') return 'dot--arrived'
  return 'dot--moving'
}

function kindOf(mediaType: QueueItem['mediaType']): DisplayItem['kind'] {
  if (mediaType === 'video') return 'scene'
  if (mediaType === 'audio') return 'audio'
  return 'doc'
}

function kindIcon(mediaType: QueueItem['mediaType']): string {
  if (mediaType === 'video') return Icon.videoSlate
  if (mediaType === 'audio') return Icon.micSlate
  return Icon.imageSlate
}

function toDisplayItem(item: QueueItem): DisplayItem {
  return {
    clientMediaId: item.clientMediaId,
    thumb: thumbFor(item),
    kind: kindOf(item.mediaType),
    kindIcon: kindIcon(item.mediaType),
    fileName: item.fileName,
    time: formatTime(item.createdAt),
    projectName: item.projectName,
    statusText: statusText(item.state),
    waitingText: waitingText(item),
    errorText: item.state === 'failed' ? item.errorMessage || '' : '',
    expiresText: expiresText(item),
    dotClass: dotClass(item.state),
    canRetry: item.state === 'failed',
  }
}

Page({
  data: {
    metrics: {} as Metrics,
    scrollTop: 0,
    items: [] as DisplayItem[],
  },

  unsubscribe: null as (() => void) | null,
  pollTimer: null as number | null,

  onLoad() {
    const app = getApp<AppGlobal>()
    this.setData({ metrics: app.globalData.metrics })
  },

  onShow() {
    this.refresh()
    if (!this.unsubscribe) {
      this.unsubscribe = subscribe(() => this.refresh())
    }
    this.startPolling()
  },

  onHide() {
    this.stopPolling()
  },

  onUnload() {
    this.stopPolling()
    if (this.unsubscribe) {
      this.unsubscribe()
      this.unsubscribe = null
    }
  },

  startPolling() {
    this.stopPolling()
    this.pollTimer = setInterval(() => {
      pollStatus()
    }, POLL_INTERVAL)
  },

  stopPolling() {
    if (this.pollTimer !== null) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  },

  refresh() {
    this.setData({ items: listItems().map(toDisplayItem) })
  },

  onPageScroll(e: { scrollTop: number }) {
    // 只在跨过阈值时 setData，避免每帧都触发渲染层通信
    const crossed = e.scrollTop > 4
    if (crossed !== this.data.scrollTop > 4) {
      this.setData({ scrollTop: e.scrollTop })
    }
  },

  onRetry(e: WechatMiniprogram.BaseEvent<WechatMiniprogram.IAnyObject, { id: string }>) {
    retry(e.currentTarget.dataset.id)
  },

  /** 缩略图渲染失败（临时文件被回收等）：记为 broken，刷新后回落占位 */
  onThumbError(e: WechatMiniprogram.BaseEvent<WechatMiniprogram.IAnyObject, { id: string }>) {
    markThumbBroken(e.currentTarget.dataset.id)
    this.refresh()
  },
})
