/**
 * 现场录音 —— wx.getRecorderManager() 的唯一封装（dev-board#228）。
 *
 * RecorderManager 是全局单例，onStop/onError 只在首次取用时绑定一次，
 * 绝不重复绑（重复绑会让一次停止触发多次入队）。
 *
 * 分段自动续录：单段最长 10 分钟（RecorderManager 的 duration 上限），
 * 时长到顶 onStop 自动开下一段；手动停止用 manualStop 意图标志区分，
 * 避免 onStop 的「到顶还是用户停」二义。每段经 enqueueCapture 入上传队列，
 * 段号从 1 递增，文件名形如 录音_yyyyMMdd_HHmmss_段N.mp3。
 */

import type { RelayProject } from './api'
import { enqueueCapture } from './queue'

/** 单段最长 10 分钟——RecorderManager 的上限 */
export const SEGMENT_DURATION_MS = 600000

export interface RecorderCallbacks {
  /** 到顶自动续录、开出新一段时回调（首段不回调），带新段号 */
  onSegment: (segmentIndex: number) => void
  /** 手动停止、末段已入队后回调 */
  onFinish: () => void
  /** 录音出错（含续录失败），会话已结束 */
  onError: (message: string) => void
}

interface Session extends RecorderCallbacks {
  project: RelayProject
  segmentIndex: number
  manualStop: boolean
}

let manager: WechatMiniprogram.RecorderManager | null = null
let session: Session | null = null

function getManager(): WechatMiniprogram.RecorderManager {
  if (manager) return manager
  manager = wx.getRecorderManager()

  manager.onStop((res) => {
    const s = session
    if (!s) return
    if (res.tempFilePath) {
      enqueueCapture(res.tempFilePath, 'audio', s.project, s.segmentIndex)
    }
    if (s.manualStop) {
      session = null
      s.onFinish()
    } else {
      // 时长到顶：静默续录下一段（不弹窗，与录像的逐段确认刻意不同）
      s.segmentIndex += 1
      s.onSegment(s.segmentIndex)
      startSegment()
    }
  })

  manager.onError(() => {
    const s = session
    if (!s) return
    session = null
    s.onError('录音出错，已停止；已录内容会照常上传')
  })

  return manager
}

function startSegment(): void {
  // mp3 + 16kHz 单声道是 RecorderManager 的合法组合（16000 允许码率 24k-96k），
  // 语音留证够用且体积小。
  getManager().start({
    format: 'mp3',
    sampleRate: 16000,
    numberOfChannels: 1,
    encodeBitRate: 48000,
    duration: SEGMENT_DURATION_MS,
  })
}

/**
 * 录音权限：先 authorize；被拒过的话 authorize 直接 fail，
 * 引导去设置页开「麦克风」再回来。
 */
function ensureRecordAuth(): Promise<boolean> {
  return new Promise((resolve) => {
    wx.authorize({
      scope: 'scope.record',
      success: () => resolve(true),
      fail: () => {
        wx.showModal({
          title: '需要麦克风权限',
          content: '录音需要使用麦克风。请在设置里打开「麦克风」权限后重试。',
          confirmText: '去设置',
          success: (res) => {
            if (!res.confirm) {
              resolve(false)
              return
            }
            wx.openSetting({
              success: (s) => resolve(!!s.authSetting['scope.record']),
              fail: () => resolve(false),
            })
          },
          fail: () => resolve(false),
        })
      },
    })
  })
}

export function isRecording(): boolean {
  return session !== null
}

/** 开始一次录音会话；返回是否真的开录了（权限被拒 / 已在录则 false）。 */
export async function startRecording(project: RelayProject, callbacks: RecorderCallbacks): Promise<boolean> {
  if (session) return false
  const ok = await ensureRecordAuth()
  if (!ok) return false
  session = { project, segmentIndex: 1, manualStop: false, ...callbacks }
  startSegment()
  return true
}

/** 手动停止：末段在 onStop 里入队后回调 onFinish。 */
export function stopRecording(): void {
  if (!session) return
  session.manualStop = true
  getManager().stop()
}
