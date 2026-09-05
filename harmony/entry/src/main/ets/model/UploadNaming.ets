import { MediaKind, MediaKindOps } from './Capture'
import { tr } from '../design/L10n'

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

/**
 * 上传文件名。带上采集时刻，桌面端按名字排序即是时间序；不用原始 UUID 当名字——
 * 律师在文件夹里看到一串十六进制没有任何意义。与 iOS / 安卓逐字一致。
 */
export function uploadFileName(kind: MediaKind, capturedAtMs: number, clientMediaId: string): string {
  const prefix: string = kind === MediaKind.audio ? tr('file.prefix.audio') : tr('file.prefix.media')
  const d: Date = new Date(capturedAtMs)
  const day: string = `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}`
  const time: string = `${pad2(d.getHours())}${pad2(d.getMinutes())}${pad2(d.getSeconds())}`
  const short: string = clientMediaId.substring(0, 4)
  return `${prefix}-${day}-${time}-${short}.${MediaKindOps.ext(kind)}`
}
