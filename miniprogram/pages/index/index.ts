import { Icon } from '../../utils/icons'
import type { Metrics } from '../../utils/layout'
import { getSession, getSelectedProject, type RelayProject } from '../../utils/api'
import { listItems, counts, subscribe, pollStatus, processQueue, enqueueCapture, type QueueItem } from '../../utils/queue'

interface AppGlobal {
  globalData: { metrics: Metrics }
}

/** 队列轮询节奏：5 秒一次，见实施契约 §3 */
const POLL_INTERVAL = 5000

/** 首页缩略图用的精简展示结构 */
interface RecentItem {
  id: string
  kind: 'doc' | 'scene'
  state: 'waiting' | 'moving' | 'arrived'
  time: string
}

/** 队列的五态收窄成首页缩略图用的三态：waiting/failed 都算「还没走」 */
function toDisplayState(state: QueueItem['state']): 'waiting' | 'moving' | 'arrived' {
  if (state === 'waiting' || state === 'failed') return 'waiting'
  if (state === 'arrived') return 'arrived'
  return 'moving'
}

function formatTime(ts: number): string {
  const d = new Date(ts)
  const hh = `${d.getHours()}`.padStart(2, '0')
  const mm = `${d.getMinutes()}`.padStart(2, '0')
  return `${hh}:${mm}`
}

/** 今天的归档路径，取本机时区 */
function todayArchivePath(): string {
  const d = new Date()
  const y = d.getFullYear()
  const m = `${d.getMonth() + 1}`.padStart(2, '0')
  const day = `${d.getDate()}`.padStart(2, '0')
  return `现场影像 / ${y}-${m}-${day}`
}

Page({
  data: {
    Icon,
    metrics: {} as Metrics,
    scrollTop: 0,
    project: { name: '', archivePath: '' },
    deviceName: '',
    counts: { waiting: 0, moving: 0, arrived: 0 },
    recent: [] as RecentItem[],
  },

  unsubscribe: null as (() => void) | null,
  pollTimer: null as number | null,

  onLoad() {
    const app = getApp<AppGlobal>()
    this.setData({ metrics: app.globalData.metrics })
  },

  onShow() {
    // 守门：无会话去登录，有会话无选中项目去项目选择。守门没过就不渲染真数据。
    if (!getSession()) {
      wx.reLaunch({ url: '/pages/login/login' })
      return
    }
    const project = getSelectedProject()
    if (!project) {
      wx.reLaunch({ url: '/pages/project/project' })
      return
    }

    this.setData({
      project: { name: project.name, archivePath: todayArchivePath() },
      deviceName: project.deviceName || '桌面设备',
    })

    this.refresh()
    if (!this.unsubscribe) {
      this.unsubscribe = subscribe(() => this.refresh())
    }
    this.startPolling()
    // 启动时未登录的话 recoverOnLaunch 不动队列；守门通过说明已登录，
    // 这里把遗留的待上传项带起来（幂等，单飞锁挡重复）。
    processQueue()
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
    const recent: RecentItem[] = listItems()
      .slice(0, 6)
      .map((item) => ({
        id: item.clientMediaId,
        kind: item.mediaType === 'video' ? 'scene' : 'doc',
        state: toDisplayState(item.state),
        time: formatTime(item.createdAt),
      }))
    this.setData({ counts: counts(), recent })
  },

  onPageScroll(e: { scrollTop: number }) {
    // 只在跨过阈值时 setData，避免每帧都触发渲染层通信
    const crossed = e.scrollTop > 4
    if (crossed !== this.data.scrollTop > 4) {
      this.setData({ scrollTop: e.scrollTop })
    }
  },

  async onCapture() {
    wx.vibrateShort({ type: 'light' })
    const project = getSelectedProject()
    if (!project) return

    const media = await this.captureMedia(['image', 'video'])
    if (!media) return

    if (media.type === 'video') {
      enqueueCapture(media.tempFilePath, 'video', project, 1)
      await this.recordMoreSegments(project, 1)
    } else {
      enqueueCapture(media.tempFilePath, 'image', project)
    }
  },

  /** 单段录满后询问是否续录下一段，取消则结束循环 */
  async recordMoreSegments(project: RelayProject, segmentIndex: number) {
    const { confirm } = await wx.showModal({
      title: `已录制第 ${segmentIndex} 段（单段最长 60 秒）`,
      content: '继续录制下一段吗？',
    })
    if (!confirm) return

    const media = await this.captureMedia(['video'])
    if (!media) return

    const next = segmentIndex + 1
    enqueueCapture(media.tempFilePath, 'video', project, next)
    await this.recordMoreSegments(project, next)
  },

  /** 拉起相机；用户取消不算错误，只有非取消的失败才提示 */
  async captureMedia(
    mediaType: Array<'image' | 'video'>
  ): Promise<{ type: string; tempFilePath: string } | null> {
    try {
      const res = await wx.chooseMedia({
        count: 1,
        mediaType,
        sourceType: ['camera'],
        maxDuration: 60,
        camera: 'back',
      })
      return { type: res.type, tempFilePath: res.tempFiles[0].tempFilePath }
    } catch (err) {
      const message = (err as { errMsg?: string })?.errMsg || ''
      if (!message.includes('cancel')) {
        wx.showToast({ title: '拍摄未完成', icon: 'none' })
      }
      return null
    }
  },

  onOpenQueue() {
    wx.navigateTo({ url: '/pages/queue/queue' })
  },

  onSwitchProject() {
    wx.navigateTo({ url: '/pages/project/project' })
  },
})
