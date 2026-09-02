/**
 * 传输阶段的展示层 —— 纯函数，不碰 wx，两端文案一致（对齐 iOS TransferPhase）。
 *
 * 内部五态（QueueState）是状态机与存储契约，不改；界面上只说三段：
 * 上传中（在手机上，含排队/传输/失败）/ 已暂存（云端等电脑）/ 已落盘（已在电脑上）。
 */

export type QueueState = 'waiting' | 'uploading' | 'uploaded' | 'arrived' | 'failed'
export type Phase = 'uploading' | 'staged' | 'landed'

export const PHASE_LABEL: Record<Phase, string> = {
  uploading: '上传中',
  staged: '已暂存',
  landed: '已落盘',
}

export function phaseOf(state: QueueState): Phase {
  if (state === 'uploaded') return 'staged'
  if (state === 'arrived') return 'landed'
  return 'uploading'
}

export function stateText(state: QueueState): string {
  switch (state) {
    case 'waiting':
    case 'uploading':
      return '上传中'
    case 'failed':
      return '上传失败'
    case 'uploaded':
      return '已暂存 · 等待桌面端接收'
    case 'arrived':
      return '已落盘'
  }
}

/** 点色：排队与传输同色（都还在手机上）；已暂存用 moving 色；失败红。令牌名不改。 */
export function dotClass(state: QueueState): string {
  if (state === 'failed') return 'dot--failed'
  if (state === 'uploaded') return 'dot--moving'
  if (state === 'arrived') return 'dot--arrived'
  return 'dot--waiting'
}

export interface Tally {
  uploading: number
  failed: number
  staged: number
  landed: number
}

export function tallyOf(items: Array<{ state: QueueState }>): Tally {
  const t: Tally = { uploading: 0, failed: 0, staged: 0, landed: 0 }
  for (const it of items) {
    t[phaseOf(it.state)]++
    if (it.state === 'failed') t.failed++
  }
  return t
}

export function tallyTotal(t: Tally): number {
  return t.uploading + t.staged + t.landed
}

/** 项目标识：key 是桌面机本地 id，跨机同号不同物，必须连 deviceId。与 iOS RelayProject.id 同构。 */
export function projectId(p: { deviceId: string; projectKey: string }): string {
  return `${p.deviceId}:${p.projectKey}`
}

export interface DaySection<T> {
  key: string
  title: string
  items: T[]
}

/** 按本机自然日分段，新的在前；段内按时间倒序。 */
export function groupByDay<T extends { createdAt: number }>(items: T[]): DaySection<T>[] {
  const map = new Map<string, { day: Date; items: T[] }>()
  for (const it of items) {
    const d = new Date(it.createdAt)
    const key = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`
    let g = map.get(key)
    if (!g) {
      g = { day: new Date(d.getFullYear(), d.getMonth(), d.getDate()), items: [] }
      map.set(key, g)
    }
    g.items.push(it)
  }
  return Array.from(map.entries())
    .sort((a, b) => b[1].day.getTime() - a[1].day.getTime())
    .map(([key, g]) => {
      const list = g.items.slice().sort((a, b) => b.createdAt - a.createdAt)
      return { key, title: `${g.day.getMonth() + 1}月${g.day.getDate()}日 · ${list.length} 件`, items: list }
    })
}

/** 删除确认文案，按所选里最坏的阶段说话。 */
export function deleteWarning(states: QueueState[]): string {
  const uploading = states.filter((s) => phaseOf(s) === 'uploading').length
  if (uploading > 0) return `其中 ${uploading} 件还没送出去。删了就没了，无法找回。`
  const staged = states.filter((s) => phaseOf(s) === 'staged').length
  if (staged > 0) return `其中 ${staged} 件电脑还没取回。中转区 7 天后清理，电脑若未及时接收，这些影像将无法找回。`
  return `删除 ${states.length} 件本地原图？电脑上已有副本。`
}

/** 可切换的项目：当前项目永远第一（哪怕还没拍），其余有记录的按名称排。 */
export function projectsIn(
  items: Array<{ deviceId: string; projectKey: string; projectName: string }>,
  current: { deviceId: string; key: string; name: string },
): Array<{ id: string; name: string }> {
  const curId = projectId({ deviceId: current.deviceId, projectKey: current.key })
  const seen = new Map<string, string>()
  for (const it of items) seen.set(projectId(it), it.projectName)
  seen.delete(curId)
  const rest = Array.from(seen.entries())
    .map(([id, name]) => ({ id, name }))
    .sort((a, b) => a.name.localeCompare(b.name, 'zh-Hans-CN'))
  return [{ id: curId, name: current.name }, ...rest]
}
