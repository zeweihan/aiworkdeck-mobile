/**
 * 单飞上传队列 —— 拍摄 → 留底 → 上传 → 等桌面端接收 的全部状态机。
 *
 * 契约见 docs/specs/2026-08-20-miniprogram-real-api.md §3。持久化在
 * wx.setStorageSync('awd.queue', QueueItem[])，每次变更都落盘并通知订阅者，
 * 页面（index/queue）靠 subscribe 刷新，不自己维护一份队列状态。
 *
 * 轮询节奏由页面控制（onShow 起 5 秒间隔、onHide 清定时器），这里只提供
 * pollStatus() 单次查询。
 */

import { ApiError, getSession, mediaStatus, uploadMedia, uuid, type RelayProject } from './api'

const STORAGE_KEY = 'awd.queue'

export type QueueState = 'waiting' | 'uploading' | 'uploaded' | 'arrived' | 'failed'

export interface QueueItem {
  /** uuid()，幂等键，重传不产生重复件 */
  clientMediaId: string
  /** 照片_20260820_141516.jpg / 录像_20260820_141516_段1.mp4 / 录音_20260820_141516_段1.mp3 */
  fileName: string
  mediaType: 'image' | 'video' | 'audio'
  /** saveFile 后的沙盒路径；saveFile 失败时是临时路径 */
  filePath: string
  saved: boolean
  deviceId: string
  projectKey: string
  projectName: string
  /** ISO8601 */
  capturedAt: string
  state: QueueState
  errorMessage?: string
  /** uploaded 态由 status 轮询回填 */
  waitingSeconds?: number
  /** 中转区到期时刻（ISO 本地时间字符串），uploaded 未抵达件由 status 轮询回填 */
  expiresAt?: string
  /** 录像/录音分段序号，从 1 起 */
  segmentIndex?: number
  /** Date.now()，列表排序与显示 HH:mm 用 */
  createdAt: number
  /** 已失败的次数，超过 MAX_AUTO_RETRIES 后不再自动重试，只留手动 retry() */
  attempts?: number
}

// ---------- 持久化 + 订阅通知 ----------

const listeners: Array<() => void> = []

export function subscribe(cb: () => void): () => void {
  listeners.push(cb)
  return () => {
    const idx = listeners.indexOf(cb)
    if (idx >= 0) listeners.splice(idx, 1)
  }
}

function notify(): void {
  listeners.forEach((cb) => cb())
}

function readItems(): QueueItem[] {
  const v = wx.getStorageSync(STORAGE_KEY)
  return Array.isArray(v) ? (v as QueueItem[]) : []
}

function writeItems(items: QueueItem[]): void {
  wx.setStorageSync(STORAGE_KEY, items)
  notify()
}

function updateItem(clientMediaId: string, mutate: (item: QueueItem) => void): void {
  const items = readItems()
  const item = items.find((it) => it.clientMediaId === clientMediaId)
  if (!item) return
  mutate(item)
  writeItems(items)
}

// ---------- 查询 ----------

/** 新 → 旧。 */
export function listItems(): QueueItem[] {
  return readItems()
    .slice()
    .sort((a, b) => b.createdAt - a.createdAt)
}

export function counts(): { waiting: number; moving: number; arrived: number } {
  let waiting = 0
  let moving = 0
  let arrived = 0
  for (const it of readItems()) {
    if (it.state === 'waiting' || it.state === 'failed') waiting++
    else if (it.state === 'uploading' || it.state === 'uploaded') moving++
    else if (it.state === 'arrived') arrived++
  }
  return { waiting, moving, arrived }
}

// ---------- 文件名 ----------

function pad2(n: number): string {
  return n < 10 ? '0' + n : String(n)
}

function fileNameFor(mediaType: 'image' | 'video' | 'audio', at: Date, segmentIndex?: number): string {
  const stamp =
    `${at.getFullYear()}${pad2(at.getMonth() + 1)}${pad2(at.getDate())}_` +
    `${pad2(at.getHours())}${pad2(at.getMinutes())}${pad2(at.getSeconds())}`
  if (mediaType === 'image') {
    return `照片_${stamp}.jpg`
  }
  if (mediaType === 'audio') {
    return `录音_${stamp}_段${segmentIndex ?? 1}.mp3`
  }
  return `录像_${stamp}_段${segmentIndex ?? 1}.mp4`
}

// ---------- 入队 ----------

/**
 * 尝试用 FileSystemManager.saveFile 把临时文件留底到沙盒（不进相册，D4）；
 * 拍摄用的 tempFilePath 在当次运行结束后可能被系统回收，留底失败就继续用
 * 临时路径上传（saved 保持 false，不阻塞流程）。
 */
export function enqueueCapture(
  tempFilePath: string,
  mediaType: 'image' | 'video' | 'audio',
  project: RelayProject,
  segmentIndex?: number,
): QueueItem {
  const now = new Date()
  const item: QueueItem = {
    clientMediaId: uuid(),
    fileName: fileNameFor(mediaType, now, segmentIndex),
    mediaType,
    filePath: tempFilePath,
    saved: false,
    deviceId: project.deviceId,
    projectKey: project.key,
    projectName: project.name,
    capturedAt: now.toISOString(),
    state: 'waiting',
    segmentIndex,
    createdAt: now.getTime(),
  }

  const items = readItems()
  items.push(item)
  writeItems(items)

  try {
    wx.getFileSystemManager().saveFile({
      tempFilePath,
      success: (res) => {
        updateItem(item.clientMediaId, (it) => {
          it.filePath = res.savedFilePath
          it.saved = true
        })
        processQueue()
      },
      fail: () => {
        // 留底失败：保持临时路径继续（saved 已是 false），不影响上传。
        processQueue()
      },
    })
  } catch {
    processQueue()
  }

  return item
}

// ---------- 上传（单飞） ----------

let uploading = false

/** 退避间隔（毫秒），按第几次失败取值；用完这些档位还失败就落到终态 failed。 */
const RETRY_DELAYS_MS = [5000, 15000, 45000]
/** 自动重试的次数上限；超过后落到终态 failed，只留手动 retry() 入口。 */
const MAX_AUTO_RETRIES = RETRY_DELAYS_MS.length

/** 失败后延迟回拨成 waiting 再续队列；不是忙循环。 */
function scheduleRetry(clientMediaId: string, attempts: number): void {
  const delay = RETRY_DELAYS_MS[attempts - 1]
  setTimeout(() => {
    updateItem(clientMediaId, (it) => {
      if (it.state === 'failed') it.state = 'waiting'
    })
    processQueue()
  }, delay)
}

/**
 * 启动恢复（app.onLaunch 调一次）：单飞锁只在内存里，上次运行在上传途中被杀的话
 * 条目会永远卡在 uploading 态——回拨成 waiting 接着传。未登录时不动队列，
 * 免得启动期就触发 4010 跳转，登录后守门页面自然会带起 processQueue。
 */
export function recoverOnLaunch(): void {
  const items = readItems()
  let changed = false
  for (const it of items) {
    if (it.state === 'uploading') {
      it.state = 'waiting'
      changed = true
    } else if (it.state === 'failed' && (it.attempts ?? 0) <= MAX_AUTO_RETRIES) {
      it.state = 'waiting'
      changed = true
    }
  }
  if (changed) writeItems(items)
  if (getSession()) processQueue()
}

/** 逐个（单飞）把 waiting → uploading → uploaded；失败 → failed，继续下一个。 */
export function processQueue(): void {
  if (uploading) return
  const next = readItems().find((it) => it.state === 'waiting')
  if (!next) return

  uploading = true
  updateItem(next.clientMediaId, (it) => {
    it.state = 'uploading'
    it.errorMessage = undefined
  })

  uploadMedia({
    filePath: next.filePath,
    deviceId: next.deviceId,
    projectKey: next.projectKey,
    clientMediaId: next.clientMediaId,
    fileName: next.fileName,
    mediaType: next.mediaType,
    capturedAt: next.capturedAt,
  })
    .then(() => {
      updateItem(next.clientMediaId, (it) => {
        it.state = 'uploaded'
      })
      uploading = false
      processQueue()
    })
    .catch((e: unknown) => {
      uploading = false
      if (e instanceof ApiError && e.code === 4010) {
        // api 层已经清会话并 reLaunch 到登录页了，这里停住即可，
        // 不重复弹窗、不继续处理队列（登录后由页面重新触发）。
        return
      }
      const attempts = (next.attempts ?? 0) + 1
      updateItem(next.clientMediaId, (it) => {
        it.state = 'failed'
        it.errorMessage = e instanceof Error ? e.message : '上传失败'
        it.attempts = attempts
      })
      if (attempts <= MAX_AUTO_RETRIES) {
        scheduleRetry(next.clientMediaId, attempts)
      }
      processQueue()
    })
}

export function retry(clientMediaId: string): void {
  updateItem(clientMediaId, (it) => {
    if (it.state === 'failed') {
      it.state = 'waiting'
      it.errorMessage = undefined
      it.attempts = 0
    }
  })
  processQueue()
}

// ---------- 状态轮询 ----------

function removeSavedFile(filePath: string): void {
  try {
    wx.getFileSystemManager().removeSavedFile({
      filePath,
      fail: () => {
        /* 留底文件删不掉不影响主流程，忽略 */
      },
    })
  } catch {
    /* 忽略 */
  }
}

/**
 * 只对 state === 'uploaded' 的项查状态；没有这类项直接 resolve(false)，不发请求。
 * delivered → arrived + 删本地留底文件；未 delivered → 回填 waitingSeconds。
 * 返回值：这批查询里是否还有项未抵达（供页面判断要不要继续等）。
 */
export function pollStatus(): Promise<boolean> {
  const uploaded = readItems().filter((it) => it.state === 'uploaded')
  if (uploaded.length === 0) return Promise.resolve(false)

  return mediaStatus(uploaded.map((it) => it.clientMediaId)).then((statuses) => {
    const byId = new Map(statuses.map((s) => [s.clientMediaId, s]))
    let stillPending = false

    for (const it of uploaded) {
      const status = byId.get(it.clientMediaId)
      if (!status) continue
      if (status.delivered) {
        updateItem(it.clientMediaId, (x) => {
          x.state = 'arrived'
        })
        if (it.saved) removeSavedFile(it.filePath)
      } else {
        updateItem(it.clientMediaId, (x) => {
          x.waitingSeconds = status.waitingSeconds
          x.expiresAt = status.expiresAt
        })
        stillPending = true
      }
    }

    return stillPending
  })
}
