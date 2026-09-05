import { ContractStates, Transition } from 'contract'
import { tr } from '../design/L10n'

/**
 * 一张影像在「拍摄 → 抵达电脑」链上的位置。名称、别名、迁移表、文案键全部来自 ContractStates。
 * ArkTS 不许给 enum 挂方法，所有行为落在 TransferStateOps 的静态方法上。
 */
export enum TransferState {
  waiting = 'waiting',
  uploading = 'uploading',
  uploaded = 'uploaded',
  arrived = 'arrived',
  failed = 'failed',
}

export enum TransferEvent {
  kick = 'kick',
  http2xx = 'http_2xx',
  httpError = 'http_error',
  networkError = 'network_error',
  retryManual = 'retry_manual',
  retryAuto = 'retry_auto',
  statusDelivered = 'status_delivered',
  statusPending = 'status_pending',
  appLaunch = 'app_launch',
}

export enum TransferPhase {
  uploading = 'uploading',
  staged = 'staged',
  landed = 'landed',
}

export interface StatusMerge {
  state: TransferState
  waitingSeconds: number | null
  expiresAt: string | null
}

/** 契约表查值。缺键是契约与端不同步，早炸早知道，不要默默给错颜色或错文案。 */
function need(table: Record<string, string>, key: string): string {
  const v: string | undefined = table[key]
  if (v === undefined) throw new Error(`contract table has no key: ${key}`)
  return v
}

const STATES: TransferState[] = [
  TransferState.waiting, TransferState.uploading, TransferState.uploaded,
  TransferState.arrived, TransferState.failed,
]
const PHASES: TransferPhase[] = [TransferPhase.uploading, TransferPhase.staged, TransferPhase.landed]

export class TransferStateOps {
  /** 旧值（如 moving）按契约别名解码；编码始终用正式名。认不出来给 null。 */
  static fromRaw(s: string): TransferState | null {
    const alias: string | undefined = ContractStates.aliases[s]
    const canonical: string = alias === undefined ? s : alias
    for (const v of STATES) {
      const raw: string = v
      if (raw === canonical) return v
    }
    return null
  }

  /** 迁移表驱动。无规则 → null（非法迁移）；有规则但 guard 不满足 → 原态。 */
  static next(s: TransferState, e: TransferEvent, attempts: number): TransferState | null {
    const from: string = s
    const event: string = e
    const rules: Transition[] = ContractStates.transitions.filter(
      (r: Transition) => r.from === from && r.event === event)
    if (rules.length === 0) return null
    for (const r of rules) {
      if (!TransferStateOps.guardOk(r.guard, attempts)) continue
      const to: TransferState | null = TransferStateOps.fromRaw(r.to)
      if (to === null) throw new Error(`contract transition target unknown: ${r.to}`)
      return to
    }
    return s
  }

  /** 冷启动回拨 = app_launch 事件；没规则就留在原态。 */
  static recovered(s: TransferState, attempts: number): TransferState {
    const n: TransferState | null = TransferStateOps.next(s, TransferEvent.appLaunch, attempts)
    return n === null ? s : n
  }

  /** status 轮询只对 uploaded 有意义；delivered 清掉等待字段，pending 回填。 */
  static applyingStatus(s: TransferState, delivered: boolean, waitingSeconds: number,
    expiresAt: string | null): StatusMerge {
    if (s !== TransferState.uploaded) {
      const idle: StatusMerge = { state: s, waitingSeconds: null, expiresAt: null }
      return idle
    }
    if (delivered) {
      const n: TransferState | null = TransferStateOps.next(s, TransferEvent.statusDelivered, 0)
      const done: StatusMerge = { state: n === null ? s : n, waitingSeconds: null, expiresAt: null }
      return done
    }
    const p: TransferState | null = TransferStateOps.next(s, TransferEvent.statusPending, 0)
    const pending: StatusMerge = {
      state: p === null ? s : p, waitingSeconds: waitingSeconds, expiresAt: expiresAt,
    }
    return pending
  }

  static phaseOf(s: TransferState): TransferPhase {
    const raw: string = need(ContractStates.phaseOf, s)
    for (const p of PHASES) {
      const pr: string = p
      if (pr === raw) return p
    }
    throw new Error(`contract phase unknown: ${raw}`)
  }

  static caption(s: TransferState): string {
    return tr(need(ContractStates.stateTextKey, s))
  }

  static detail(s: TransferState): string {
    return tr(need(ContractStates.stateDetailKey, s))
  }

  static whereItIs(s: TransferState): string {
    return tr(need(ContractStates.whereKey, s))
  }

  static phaseCaption(p: TransferPhase): string {
    return tr(need(ContractStates.phaseLabelKey, p))
  }

  /** 状态点令牌名（'S.waiting' 等），交给 Tk.color 解析成颜色。 */
  static dotToken(s: TransferState): string {
    if (s === TransferState.failed) return ContractStates.failedDot
    return need(ContractStates.phaseDot, TransferStateOps.phaseOf(s))
  }

  private static guardOk(guard: string | undefined, attempts: number): boolean {
    if (guard === undefined) return true
    if (guard === 'attempts <= maxAutoRetries') return attempts <= ContractStates.maxAutoRetries
    throw new Error(`contract guard unknown: ${guard}`)
  }
}
