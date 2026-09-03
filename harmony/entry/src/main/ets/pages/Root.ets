import { tr } from '../design/L10n'
import { Tk } from '../design/Tokens'
import { GlassBar, Pill, PrimaryButton, StatusDot } from '../design/Components'
import { CaptureItem, CaptureManifest, MediaKind, RelayProject, projectId } from '../model/Capture'
import { TransferState, TransferStateOps } from '../model/TransferState'
import { Tally, tallyOf } from '../model/TransferTally'
import { DaySection, groupByDay } from '../model/LibraryGrouping'
import { uploadFileName } from '../model/UploadNaming'
import { formatIso } from '../model/IsoTime'
import { RecordingClock } from '../model/RecordingClock'
import { Backoff } from '../model/Backoff'
import { isDesktopOnline, otherPendingCount } from '../model/AppModelLogic'
import { checkEnvelope } from '../model/Envelope'
import { BASE_URL, ServiceLocator } from '../services/ServiceLocator'
import { KickResult } from '../services/UploadQueue'

/**
 * 临时探针：领域层与设计层还没接页面，在这里各引一次，好让 hvigor 的 ArkTS 检查覆盖到它们。
 * 后续任务用真正的 Navigation 栈替换整个文件。
 */
function probe(): number {
  const now: number = 0
  const manifest: CaptureManifest = {
    clientMediaId: 'probe', sha256: '', capturedAt: formatIso(now),
    deviceModel: '', osVersion: '', appVersion: '', fromCamera: true,
  }
  const project: RelayProject = { deviceId: 'dev', key: 'proj', name: 'probe' }
  const item: CaptureItem = new CaptureItem('probe', MediaKind.photo, TransferState.waiting,
    manifest, '', 0, null, false, project)
  const tally: Tally = tallyOf([item.state, TransferState.arrived])
  const sections: DaySection[] = groupByDay([item])
  const clock: RecordingClock = new RecordingClock()
  clock.start(now)
  const backoff: Backoff = new Backoff()
  backoff.onFailure(now)
  const payload: Record<string, Object> = { 'code': 0 }
  checkEnvelope(payload)
  const names: string[] = [
    projectId(project),
    uploadFileName(item.kind, item.capturedAtMs(), item.id),
    TransferStateOps.caption(item.state),
  ]
  // 服务层：只引，不调用需要 context 的方法（装配在 EntryAbility.onCreate）
  const wired: number = ServiceLocator.isReady() ? 1 : 0
  const kicked: string = KickResult.done
  return tally.total + sections.length + names.length + clock.elapsed(now) +
    backoff.seconds + otherPendingCount([item], null) + (isDesktopOnline(null, now) ? 1 : 0) +
    wired + BASE_URL.length + kicked.length
}

@Entry
@Component
struct Root {
  private readonly probed: number = probe()

  build() {
    Column({ space: Tk.Sp.s4 }) {
      GlassBar() {
        Text(tr('home.eyebrow'))
          .fontSize(Tk.Ty.title)
          .fontColor(Tk.D.fg)
          .padding(Tk.Sp.s4)
      }
      StatusDot({ color: Tk.color(TransferStateOps.dotToken(TransferState.waiting)), dotSize: 6 })
      Pill({ label: `${this.probed}`, selected: true })
      PrimaryButton({ label: tr('home.eyebrow') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Tk.L.bg)
  }
}
