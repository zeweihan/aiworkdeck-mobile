import { ContractStates } from 'contract'
import { CaptureItem } from './Capture'
import { TransferState, TransferPhase, TransferStateOps } from './TransferState'
import { tr } from '../design/L10n'

export interface DaySection {
  key: string
  title: string
  items: CaptureItem[]
}

export interface DeleteWarn {
  level: string
  n: number
}

function need(table: Record<string, string>, key: string): string {
  const v: string | undefined = table[key]
  if (v === undefined) throw new Error(`contract table has no key: ${key}`)
  return v
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

/** 按本地自然日分段，新的在前；段内按时间倒序。段头「M月d日 · N 件」。 */
export function groupByDay(items: CaptureItem[]): DaySection[] {
  const buckets: Map<string, CaptureItem[]> = new Map<string, CaptureItem[]>()
  const keys: string[] = []
  for (const it of items) {
    const d: Date = new Date(it.capturedAtMs())
    const key: string = `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
    let bucket: CaptureItem[] | undefined = buckets.get(key)
    if (bucket === undefined) {
      bucket = []
      buckets.set(key, bucket)
      keys.push(key)
    }
    bucket.push(it)
  }
  keys.sort()
  keys.reverse()
  const sections: DaySection[] = []
  for (const key of keys) {
    const bucket: CaptureItem[] = buckets.get(key)!
    bucket.sort((a: CaptureItem, b: CaptureItem) => b.capturedAtMs() - a.capturedAtMs())
    const d: Date = new Date(bucket[0].capturedAtMs())
    const vars: Record<string, string | number> = {
      'm': d.getMonth() + 1, 'd': d.getDate(), 'n': bucket.length,
    }
    const section: DaySection = { key: key, title: tr('library.dayTitle', vars), items: bucket }
    sections.push(section)
  }
  return sections
}

/** 删除确认等级：按所选里最坏的桶说话。n = 该桶件数；landed 时 n = 总数。 */
export function deleteWarningLevel(states: TransferState[]): DeleteWarn {
  for (const phase of ContractStates.deleteWarnOrder) {
    if (phase === 'landed') break
    let n: number = 0
    for (const s of states) {
      const p: string = TransferStateOps.phaseOf(s)
      if (p === phase) n++
    }
    if (n > 0) {
      const worst: DeleteWarn = { level: need(ContractStates.deleteWarnLevel, phase), n: n }
      return worst
    }
  }
  const landed: DeleteWarn = { level: need(ContractStates.deleteWarnLevel, 'landed'), n: states.length }
  return landed
}

export function deleteWarning(states: TransferState[]): string {
  const w: DeleteWarn = deleteWarningLevel(states)
  const vars: Record<string, string | number> = { 'n': w.n }
  return tr(need(ContractStates.deleteWarnKey, w.level), vars)
}
