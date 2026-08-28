/**
 * 缩略图接线 —— 纯 UI 层，不碰 utils/queue.ts 的队列契约。
 *
 * 照片直接用 QueueItem.filePath 渲染；录像文件（mp4）没法喂给 <image>，
 * 相机 stopRecord / chooseMedia 会顺手给一张临时帧图，记在这张内存表里
 * （clientMediaId → tempThumbPath）。临时帧图只活在本次运行，重启后
 * 自然回落到占位图标，不做持久化——为一条 6 件的最近列表管理落盘生命周期不值得。
 *
 * 渲染失败的路径（临时文件被系统回收等）记进 broken 集合，binderror 后
 * 刷新即回落占位，不反复重试。
 */

import type { QueueItem } from './queue'

const videoThumbs = new Map<string, string>()
const broken = new Set<string>()

/** 录像入队后登记帧图临时路径 */
export function setVideoThumb(clientMediaId: string, thumbPath: string): void {
  if (thumbPath) videoThumbs.set(clientMediaId, thumbPath)
}

/** <image> binderror 后调用：该条目回落占位图标，不再尝试渲染 */
export function markThumbBroken(clientMediaId: string): void {
  broken.add(clientMediaId)
}

/** 条目的可渲染缩略图路径；audio / 无帧图 / 已知渲染失败 → 空串（用占位图标） */
export function thumbFor(item: Pick<QueueItem, 'clientMediaId' | 'mediaType' | 'filePath'>): string {
  if (broken.has(item.clientMediaId)) return ''
  if (item.mediaType === 'image') return item.filePath
  if (item.mediaType === 'video') return videoThumbs.get(item.clientMediaId) || ''
  return ''
}
