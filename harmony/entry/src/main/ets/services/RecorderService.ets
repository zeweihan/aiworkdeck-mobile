import { abilityAccessCtrl, bundleManager, PermissionRequestResult, Permissions, Want, wantAgent, WantAgent } from '@kit.AbilityKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import { util } from '@kit.ArkTS'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { CaptureItem, MediaKind, RelayProject } from '../model/Capture'
import { Loc } from './EvidenceStore'
import { RecordingState } from './RecordingState'
import { ServiceLocator } from './ServiceLocator'

const DOMAIN: number = 0x0000
const TAG: string = 'RecorderService'

const MIC: Permissions = 'ohos.permission.MICROPHONE'

const PROFILE: media.AVRecorderProfile = {
  audioBitrate: 64000,
  audioChannels: 1,
  audioCodec: media.CodecMimeType.AUDIO_AAC,
  audioSampleRate: 44100,
  fileFormat: media.ContainerFormatType.CFT_MPEG_4A,
}

/**
 * 录音（纯音频）。AVRecorder + AUDIO_RECORDING 长时任务 + 中断后自动续录，对位
 * 安卓 `RecordingService.kt` 的前台服务，见 `docs/specs/2026-09-03-background-recording-design.md`。
 *
 * 进程级单例：录音要跨过取景页的生死（切后台、锁屏都继续录，页面可能已经销毁重建），
 * 界面只读 `state`、只调 `start/stop`。
 *
 * 中断的信号来自 `on('stateChange')` 而不是 `on('audioInterrupt')`——API 26 的
 * `media.AVRecorder` 没有 audioInterrupt 事件（那是 AVPlayer 的），系统抢走麦克风时
 * 录音机被置为 `paused`，焦点还回来时自己回到 `started`。焦点没自动还回来的情形
 * （通话结束用户直接切回应用）由 `resumeIfInterrupted()` 补一刀。
 */
export class RecorderService {
  static readonly shared: RecorderService = new RecorderService()

  readonly state: RecordingState = new RecordingState()
  /** 落库完成后回调一件。`AppModel` 收到后重读库。 */
  onStored: ((item: CaptureItem) => void) | null = null

  private recorder: media.AVRecorder | null = null
  private file: fs.File | null = null
  private path: string = ''
  /** 开录**时**的项目与位置快照：录到一半换项目不该改写这一件的归属。 */
  private project: RelayProject | null = null
  private loc: Loc | null = null
  private bgRunning: boolean = false
  private busy: boolean = false

  // MARK: - 开录

  /**
   * 开录。任何一步失败都把已经做成的部分退回去（长时任务、录音机、文件描述符、空文件），
   * 返回 false 让界面照常留在待机态——半开的录音机比不录更糟。
   */
  async start(project: RelayProject | null, loc: Loc | null): Promise<boolean> {
    if (this.busy || this.state.isRecording) return false
    this.busy = true
    try {
      return await this.startInner(project, loc)
    } finally {
      this.busy = false
    }
  }

  private async startInner(project: RelayProject | null, loc: Loc | null): Promise<boolean> {
    if (!await this.grantMic()) {
      hilog.warn(DOMAIN, TAG, '%{public}s', 'start aborted: microphone permission denied')
      return false
    }
    // 长时任务先申请再开录音机：系统在长时任务批下来之前就把应用挂起的话，录音机会被一起冻住
    if (!await this.startBackground()) return false

    const dir: string = ServiceLocator.ctx.cacheDir
    const path: string = `${dir}/rec-${util.generateRandomUUID(false).toLowerCase()}.m4a`
    let file: fs.File
    try {
      file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'open cache file failed: %{public}s', messageOf(e))
      await this.stopBackground()
      return false
    }

    let recorder: media.AVRecorder
    try {
      recorder = await media.createAVRecorder()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'createAVRecorder failed: %{public}s', messageOf(e))
      this.closeAndRemove(file, path)
      await this.stopBackground()
      return false
    }

    this.recorder = recorder
    this.file = file
    this.path = path
    this.project = project
    this.loc = loc

    const config: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      profile: PROFILE,
      url: `fd://${file.fd}`,
    }
    try {
      // 先挂事件再 prepare：prepare/start 自己就会推状态，晚挂就会漏掉第一条
      this.listen(recorder)
      await recorder.prepare(config)
      await recorder.start()
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'prepare/start failed: %{public}s', messageOf(e))
      try {
        await recorder.release()
      } catch (e2) {
        hilog.warn(DOMAIN, TAG, 'release after failed start: %{public}s', messageOf(e2))
      }
      this.recorder = null
      this.file = null
      this.path = ''
      this.project = null
      this.loc = null
      this.closeAndRemove(file, path)
      await this.stopBackground()
      return false
    }

    this.state.begin(Date.now())
    hilog.info(DOMAIN, TAG, '%{public}s', 'recording started')
    return true
  }

  // MARK: - 停止

  /**
   * 停录并落库。幂等：重复调用（用户连点两下、系统 stopped 与界面同时到）第二次直接返回 null。
   *
   * 落库失败只记日志，**不删文件**——录到的东西是不可复现的，宁可留一个孤儿在 cacheDir
   * 里等人工捞，也不能因为写 manifest 出错就把它抹掉。
   */
  async stop(): Promise<CaptureItem | null> {
    if (this.busy) return null
    if (!this.state.isRecording && this.recorder === null) return null
    this.busy = true
    const startedAt: number = this.state.startedAt
    const path: string = this.path
    const project: RelayProject | null = this.project
    const loc: Loc | null = this.loc
    try {
      await this.teardown()
    } finally {
      this.state.finish()
      this.busy = false
    }
    if (path.length === 0) return null

    let item: CaptureItem
    try {
      item = await ServiceLocator.store.save(MediaKind.audio, path, startedAt, loc, project)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save failed, file kept at cacheDir: %{public}s', messageOf(e))
      return null
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'recording stored')
    // 上传不挡着返回：界面等的是「这一件已经进库」，传没传出去是队列自己的事
    ServiceLocator.queue.kick().catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'kick failed: %{public}s', messageOf(e))
    })
    const cb: ((item: CaptureItem) => void) | null = this.onStored
    if (cb !== null) cb(item)
    return item
  }

  /**
   * 中断结束后补一次续录。系统还回音频焦点时录音机通常自己回到 `started`（走 stateChange），
   * 但通话结束后用户直接切回应用的那条路上不一定有事件，所以回前台时再问一次。
   */
  async resumeIfInterrupted(): Promise<void> {
    const recorder: media.AVRecorder | null = this.recorder
    if (recorder === null || !this.state.isRecording || !this.state.interrupted) return
    try {
      await recorder.resume()
    } catch (e) {
      // 焦点还没还回来就是失败，等下一次机会，不算错误
      hilog.info(DOMAIN, TAG, 'resume not accepted yet: %{public}s', messageOf(e))
      return
    }
    this.state.markResumed(Date.now())
    hilog.info(DOMAIN, TAG, '%{public}s', 'recording resumed')
  }

  // MARK: - 事件

  private listen(recorder: media.AVRecorder): void {
    recorder.on('stateChange', (s: media.AVRecorderState, reason: media.StateChangeReason): void => {
      this.onStateChange(s, reason)
    })
    recorder.on('error', (err: BusinessError): void => {
      this.onError(err)
    })
  }

  /**
   * 录音机状态变了。只有我们自己不在 start/stop 中途时才作数——那两段里的状态跳变是
   * 我们自己发起的，再走一遍中断逻辑会把秒表算乱。
   */
  private onStateChange(s: media.AVRecorderState, reason: media.StateChangeReason): void {
    if (this.busy || !this.state.isRecording) return
    hilog.info(DOMAIN, TAG, 'state %{public}s reason %{public}d', s, reason)
    if (s === 'paused') {
      this.state.markInterrupted(Date.now())
    } else if (s === 'started') {
      this.state.markResumed(Date.now())
    } else if (s === 'stopped' || s === 'error') {
      // 系统把录音停了（焦点长期不还、达到时长上限）：按停止处理，已经录到的照样落库
      this.stop().catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, 'stop after system stop failed: %{public}s', messageOf(e))
      })
    }
  }

  private onError(err: BusinessError): void {
    hilog.error(DOMAIN, TAG, 'recorder error %{public}d: %{public}s', err.code, err.message)
    // AVRecorder 把音频焦点被抢报成一条错误，不是单独的事件
    if (err.code === media.AVErrorCode.AVERR_AUDIO_INTERRUPTED) this.state.markInterrupted(Date.now())
  }

  // MARK: - 内部

  private async grantMic(): Promise<boolean> {
    const perms: Permissions[] = [MIC]
    try {
      const res: PermissionRequestResult =
        await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(ServiceLocator.ctx, perms)
      return res.authResults.length > 0 && res.authResults.every((v: number): boolean => v === 0)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'requestPermissionsFromUser failed: %{public}s', messageOf(e))
      return false
    }
  }

  /** 长时任务。点它的系统通知回到 EntryAbility——录音中的应用必须一步能回得来。 */
  private async startBackground(): Promise<boolean> {
    try {
      const want: Want = { bundleName: bundleName(), abilityName: 'EntryAbility' }
      const info: wantAgent.WantAgentInfo = {
        wants: [want],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      }
      const agent: WantAgent = await wantAgent.getWantAgent(info)
      await backgroundTaskManager.startBackgroundRunning(
        ServiceLocator.ctx, backgroundTaskManager.BackgroundMode.AUDIO_RECORDING, agent)
      this.bgRunning = true
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'startBackgroundRunning failed: %{public}s', messageOf(e))
      return false
    }
  }

  private async stopBackground(): Promise<void> {
    if (!this.bgRunning) return
    this.bgRunning = false
    try {
      await backgroundTaskManager.stopBackgroundRunning(ServiceLocator.ctx)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s', messageOf(e))
    }
  }

  private async teardown(): Promise<void> {
    const recorder: media.AVRecorder | null = this.recorder
    const file: fs.File | null = this.file
    this.recorder = null
    this.file = null
    this.path = ''
    this.project = null
    this.loc = null
    if (recorder !== null) {
      try {
        await recorder.stop()
      } catch (e) {
        // 系统已经把它停了的情形会报 5400102，不是问题
        hilog.info(DOMAIN, TAG, 'stop skipped: %{public}s', messageOf(e))
      }
      try {
        await recorder.release()
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'release failed: %{public}s', messageOf(e))
      }
    }
    if (file !== null) closeQuietly(file)
    await this.stopBackground()
  }

  /** 开录半途失败时的收尾：文件里还什么都没有，留着只会当孤儿。 */
  private closeAndRemove(file: fs.File, path: string): void {
    closeQuietly(file)
    try {
      fs.unlinkSync(path)
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'unlink failed: %{public}s', messageOf(e))
    }
  }
}

function closeQuietly(file: fs.File): void {
  try {
    fs.closeSync(file)
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'close failed: %{public}s', messageOf(e))
  }
}

function bundleName(): string {
  const info: bundleManager.BundleInfo =
    bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
  return info.name
}

function messageOf(e: Object): string {
  if (e instanceof Error) {
    const err: Error = e as Error
    return err.message.length > 0 ? err.message : err.name
  }
  return `${e}`
}
