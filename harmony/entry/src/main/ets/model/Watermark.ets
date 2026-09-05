import { tr } from '../design/L10n'
import { Loc } from './Loc'

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

/**
 * 水印与定位芯片的纯格式化。抽出来是为了能在 Node 单测里直接对拍（`tests/harmony/watermark.test.ts`）——
 * 秒级时间与坐标精度是取证信息，格式错了不该等到人肉走查才发现。
 *
 * 与安卓 `WatermarkFormat.kt`、iOS `HomeView.stamp` 同格式：时间到秒，坐标五位小数（约 1 米量级）。
 *
 * 水印**只叠加在取景与展示层，不烧录进照片字节**：照片是 JPEG 直出保 SHA-256「原始采集」，
 * 烧录会毁掉证据链（决策 D3，三端一致）。
 */

/** 水印上的时间行。本机时区，到秒。 */
export function watermarkTime(atMs: number): string {
  const d: Date = new Date(atMs)
  const day: string = `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
  return `${day} ${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`
}

/** 水印上的坐标行。没有定位就说「定位中」——不写零零坐标，那是在编。 */
export function watermarkCoord(loc: Loc | null): string {
  if (loc === null) return tr('home.gps.none')
  const base: string = `${loc.lat.toFixed(5)}, ${loc.lon.toFixed(5)}`
  const acc: number | null = loc.accuracy
  return acc === null ? base : `${base} · ${accuracyText(acc)}`
}

/** 顶栏芯片：只给精度。没有精度的坐标在质证时说明不了问题，所以精度要直接显示出来。 */
export function gpsChip(loc: Loc | null): string {
  if (loc === null || loc.accuracy === null) return tr('home.gps.none')
  return accuracyText(loc.accuracy)
}

/** 左下角水印。没有项目名就少一行，不留空行占位。 */
export function watermarkLines(nowMs: number, projectName: string | null, loc: Loc | null): string[] {
  const lines: string[] = [watermarkTime(nowMs)]
  if (projectName !== null && projectName.length > 0) lines.push(projectName)
  lines.push(watermarkCoord(loc))
  return lines
}

function accuracyText(meters: number): string {
  return tr('home.gps.accuracy', { 'm': Math.round(meters) })
}
