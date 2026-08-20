import type { Metrics } from '../../utils/layout'
import { listItems, subscribe, pollStatus, retry, type QueueItem, type QueueState } from '../../utils/queue'

interface AppGlobal {
  globalData: { metrics: Metrics }
}

/** 队列轮询节奏：5 秒一次，见实施契约 §3 */
const POLL_INTERVAL = 5000

/** 一条队列记录在页面上展示用的精简结构 */
interface DisplayItem {
  clientMediaId: string
  fileName: string
  time: string
  projectName: string
  statusText: string
  waitingText: string
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

function dotClass(state: QueueState): string {
  if (state === 'failed') return 'dot--failed'
  if (state === 'waiting') return 'dot--waiting'
  if (state === 'arrived') return 'dot--arrived'
  return 'dot--moving'
}

function toDisplayItem(item: QueueItem): DisplayItem {
  return {
    clientMediaId: item.clientMediaId,
    fileName: item.fileName,
    time: formatTime(item.createdAt),
    projectName: item.projectName,
    statusText: statusText(item.state),
    waitingText: waitingText(item),
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
})
