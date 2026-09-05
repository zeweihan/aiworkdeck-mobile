import { TransferState, TransferPhase, TransferStateOps } from './TransferState'

/** 三桶计数。失败件不单列一桶，它是「上传中」桶里的异常，单独再数一次。 */
export interface Tally {
  uploading: number
  failed: number
  staged: number
  landed: number
  total: number
}

export function tallyOf(states: TransferState[]): Tally {
  let uploading: number = 0
  let failed: number = 0
  let staged: number = 0
  let landed: number = 0
  for (const s of states) {
    const p: TransferPhase = TransferStateOps.phaseOf(s)
    if (p === TransferPhase.uploading) uploading++
    else if (p === TransferPhase.staged) staged++
    else landed++
    if (s === TransferState.failed) failed++
  }
  const t: Tally = {
    uploading: uploading, failed: failed, staged: staged, landed: landed,
    total: uploading + staged + landed,
  }
  return t
}
