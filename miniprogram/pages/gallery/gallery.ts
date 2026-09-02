/**
 * 图集 —— 影像浏览走深色（D7）。只看一个项目：默认当前项目，点标题切换看别的项目
 * （只切看的对象，不切拍摄目标）。项目内按自然日分段。列数、网格/列表、多选删除都在这一页。
 * 队列契约不动，本页只读 listItems / 调 removeItems。
 */

import { Icon } from '../../utils/icons'
import type { Metrics } from '../../utils/layout'
import { getSelectedProject } from '../../utils/api'
import { listItems, removeItems, subscribe, pollStatus, type QueueItem } from '../../utils/queue'
import {
  deleteWarning, dotClass, groupByDay, projectsIn, stateText, tallyOf, type Tally,
} from '../../utils/phase'
import { thumbFor, markThumbBroken } from '../../utils/thumbs'

interface AppGlobal {
  globalData: { metrics: Metrics }
}

/** 与队列页同一节奏：开着图集时状态变化要在眼前翻过来 */
const POLL_INTERVAL = 5000
const KEY_COLS = 'awd.gallery.cols'
const KEY_VIEW = 'awd.gallery.view'

interface Cell {
  clientMediaId: string
  mediaType: QueueItem['mediaType']
  /** 原件路径（留底路径或临时路径），全屏预览 / 播放用 */
  filePath: string
  thumb: string
  kindIcon: string
  time: string
  statusText: string
  errorText: string
  dotClass: string
  fileName: string
  createdAt: number
  checked: boolean
}

function formatTime(ts: number): string {
  const d = new Date(ts)
  return `${`${d.getHours()}`.padStart(2, '0')}:${`${d.getMinutes()}`.padStart(2, '0')}`
}

function kindIcon(mediaType: QueueItem['mediaType']): string {
  if (mediaType === 'video') return Icon.videoWhite
  if (mediaType === 'audio') return Icon.micWhite
  return Icon.imageWhite
}

function readCols(): number {
  const v = wx.getStorageSync(KEY_COLS)
  return v === 2 || v === 3 || v === 4 ? v : 3
}

function readView(): 'grid' | 'list' {
  return wx.getStorageSync(KEY_VIEW) === 'list' ? 'list' : 'grid'
}

Page({
  data: {
    Icon,
    metrics: {} as Metrics,
    scrollTop: 0,
    viewingId: '',
    viewingName: '',
    projects: [] as Array<{ id: string; name: string }>,
    tally: { uploading: 0, failed: 0, staged: 0, landed: 0 } as Tally,
    days: [] as Array<{ key: string; title: string; items: Cell[] }>,
    cols: 3,
    view: 'grid' as 'grid' | 'list',
    selecting: false,
    selectedCount: 0,
  },

  unsubscribe: null as (() => void) | null,
  pollTimer: null as number | null,
  selected: new Set<string>(),
  /** 正在播放的录音（同一时刻最多一条） */
  audio: null as WechatMiniprogram.InnerAudioContext | null,
  audioId: '',

  onLoad() {
    const app = getApp<AppGlobal>()
    this.setData({ metrics: app.globalData.metrics, cols: readCols(), view: readView() })
  },

  onShow() {
    this.refresh()
    if (!this.unsubscribe) this.unsubscribe = subscribe(() => this.refresh())
    this.onHide()
    this.pollTimer = setInterval(() => pollStatus(), POLL_INTERVAL)
  },

  onHide() {
    if (this.pollTimer !== null) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
    this.stopAudio()
  },

  onUnload() {
    this.onHide()
    if (this.unsubscribe) {
      this.unsubscribe()
      this.unsubscribe = null
    }
  },

  onPageScroll(e: { scrollTop: number }) {
    const crossed = e.scrollTop > 4
    if (crossed !== this.data.scrollTop > 4) this.setData({ scrollTop: e.scrollTop })
  },

  refresh() {
    const current = getSelectedProject()
    if (!current) return
    const projects = projectsIn(listItems(), current)
    const viewingId = projects.some((p) => p.id === this.data.viewingId)
      ? this.data.viewingId
      : projects[0].id
    const viewingName = projects.find((p) => p.id === viewingId)!.name
    const items = listItems(viewingId)
    const cells: Cell[] = items.map((it) => ({
      clientMediaId: it.clientMediaId,
      mediaType: it.mediaType,
      filePath: it.filePath,
      thumb: thumbFor(it),
      kindIcon: kindIcon(it.mediaType),
      time: formatTime(it.createdAt),
      statusText: stateText(it.state),
      errorText: it.state === 'failed' ? it.errorMessage || '' : '',
      dotClass: dotClass(it.state),
      fileName: it.fileName,
      createdAt: it.createdAt,
      checked: this.selected.has(it.clientMediaId),
    }))
    this.setData({
      projects,
      viewingId,
      viewingName,
      tally: tallyOf(items),
      days: groupByDay(cells),
      selectedCount: this.selected.size,
    })
  },

  // ---------- 切换看的项目 ----------

  onTitleTap() {
    const names = this.data.projects.map((p) => p.name)
    if (names.length <= 1) return
    // showActionSheet 最多 6 项；现场同时有记录的项目很少超过这个数
    wx.showActionSheet({
      itemList: names.slice(0, 6),
      success: (res) => {
        this.selected.clear()
        this.setData({ viewingId: this.data.projects[res.tapIndex].id, selecting: false })
        this.refresh()
      },
    })
  },

  // ---------- 列数 / 视图 ----------

  onToggleCols() {
    const cols = this.data.cols >= 4 ? 2 : this.data.cols + 1
    wx.setStorageSync(KEY_COLS, cols)
    this.setData({ cols })
  },

  onToggleView() {
    const view = this.data.view === 'grid' ? 'list' : 'grid'
    wx.setStorageSync(KEY_VIEW, view)
    this.setData({ view })
  },

  // ---------- 多选删除 ----------

  onToggleSelecting() {
    this.selected.clear()
    this.setData({ selecting: !this.data.selecting })
    this.refresh()
  },

  onTapCell(e: WechatMiniprogram.BaseEvent<WechatMiniprogram.IAnyObject, { id: string }>) {
    const id = e.currentTarget.dataset.id
    if (!this.data.selecting) {
      this.openViewer(id)
      return
    }
    if (this.selected.has(id)) this.selected.delete(id)
    else this.selected.add(id)
    this.refresh()
  },

  // ---------- 全屏看大图：走系统接口（dev-board#387） ----------

  /**
   * 照片与录像用 wx.previewMedia：系统级全屏、左右滑同一天的其他件、缩放。
   * 它显示不了状态与哈希——核对在列表视图里看；全屏页的任务是看清画面。
   * 录音 previewMedia 不支持，用 InnerAudioContext 点播/点停。
   */
  openViewer(id: string) {
    const day = this.data.days.find((d) => d.items.some((c) => c.clientMediaId === id))
    const cell = day?.items.find((c) => c.clientMediaId === id)
    if (!day || !cell) return

    if (cell.mediaType === 'audio') {
      this.toggleAudio(cell)
      return
    }
    if (!cell.filePath) {
      wx.showToast({ title: '原件已不在本机', icon: 'none' })
      return
    }
    // previewMedia 最多 50 项；按同一天里能预览的件组
    const sources = day.items
      .filter((c) => c.mediaType !== 'audio' && c.filePath)
      .slice(0, 50)
      .map((c) => ({ url: c.filePath, type: c.mediaType as 'image' | 'video' }))
    const current = Math.max(0, sources.findIndex((s) => s.url === cell.filePath))
    wx.previewMedia({
      sources,
      current,
      fail: () => wx.showToast({ title: '打不开这件影像', icon: 'none' }),
    })
  },

  toggleAudio(cell: Cell) {
    if (this.audio && this.audioId === cell.clientMediaId) {
      this.stopAudio()
      return
    }
    this.stopAudio()
    if (!cell.filePath) {
      wx.showToast({ title: '录音原件已不在本机', icon: 'none' })
      return
    }
    const ctx = wx.createInnerAudioContext()
    ctx.src = cell.filePath
    ctx.onEnded(() => this.stopAudio())
    ctx.onError(() => {
      this.stopAudio()
      wx.showToast({ title: '播放失败', icon: 'none' })
    })
    ctx.play()
    this.audio = ctx
    this.audioId = cell.clientMediaId
    wx.showToast({ title: `播放 ${cell.time} 的录音，再点一次停止`, icon: 'none', duration: 2000 })
  },

  stopAudio() {
    if (this.audio) {
      this.audio.stop()
      this.audio.destroy()
      this.audio = null
      this.audioId = ''
    }
  },

  onDelete() {
    if (this.selected.size === 0) return
    const ids = Array.from(this.selected)
    const states = listItems(this.data.viewingId)
      .filter((it) => this.selected.has(it.clientMediaId))
      .map((it) => it.state)
    wx.showModal({
      title: `删除 ${ids.length} 件`,
      content: deleteWarning(states),
      confirmText: '删除',
      confirmColor: '#B91C1C',
      success: (res) => {
        if (!res.confirm) return
        removeItems(ids)
        this.selected.clear()
        this.setData({ selecting: false })
        this.refresh()
      },
    })
  },

  onThumbError(e: WechatMiniprogram.BaseEvent<WechatMiniprogram.IAnyObject, { id: string }>) {
    markThumbBroken(e.currentTarget.dataset.id)
    this.refresh()
  },
})
