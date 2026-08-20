/**
 * 后端 API 封装 —— 全小程序唯一网络出口。
 *
 * 契约见 docs/specs/2026-08-20-miniprogram-real-api.md §2；
 * 响应判读语义照抄 iOS 端 ios/Sources/Services/Backend.swift（信封与裸数组两种形状、
 * 网络层失败与业务失败分开说）。鉴权用 X-Session-Id 请求头，与桌面端同门
 * （见 docs/specs/2026-08-20-project-sync-relay.md）。
 */

export const BASE_URL = 'https://addin.aiworkdeck.com'

/** 统一错误：code 是信封里的业务 code；网络层/HTTP 层失败固定为 -1。 */
export class ApiError extends Error {
  code: number
  constructor(code: number, message: string) {
    super(message)
    this.code = code
    this.name = 'ApiError'
  }
}

// ---------- 会话 / 用户 / 选中项目：全部走 wx.*StorageSync ----------

const KEY_SESSION = 'awd.session'
const KEY_USER = 'awd.user'
const KEY_PROJECT = 'awd.project'

export interface AccountUser {
  id: number
  username: string
  displayName: string
}

export interface LoginResult {
  sessionId: string
  isNewUser: boolean
  user: AccountUser
}

/** 项目目录条目（桌面端推上云的镜像）。key 是桌面机本地库的项目 id，
 *  跨机同号不同物，必须连着 deviceId 一起用——上传时两个都要带。 */
export interface RelayProject {
  deviceId: string
  deviceName: string | null
  key: string
  name: string
}

export interface MediaStatus {
  clientMediaId: string
  delivered: boolean
  waitingSeconds: number
}

export function getSession(): string | null {
  const v = wx.getStorageSync(KEY_SESSION)
  return typeof v === 'string' && v ? v : null
}

export function setSession(v: string | null): void {
  if (v) {
    wx.setStorageSync(KEY_SESSION, v)
  } else {
    wx.removeStorageSync(KEY_SESSION)
  }
}

function setUser(u: AccountUser | null): void {
  if (u) {
    wx.setStorageSync(KEY_USER, u)
  } else {
    wx.removeStorageSync(KEY_USER)
  }
}

export function getSelectedProject(): RelayProject | null {
  const v = wx.getStorageSync(KEY_PROJECT)
  return v ? (v as RelayProject) : null
}

export function setSelectedProject(p: RelayProject | null): void {
  if (p) {
    wx.setStorageSync(KEY_PROJECT, p)
  } else {
    wx.removeStorageSync(KEY_PROJECT)
  }
}

// ---------- 统一响应判读 ----------

/**
 * 信封与裸数组共用一套判读，四条规则：
 * 1. HTTP 非 2xx → ApiError(-1, '服务器返回 N')。
 * 2. 体是数组 → 直接成功（裸数组端点：/projects、/media/status）。
 * 3. 体是对象且有数字 code：0 成功取 data；4010 清会话并跳登录后抛错；
 *    其他 code 原样抛错。
 * 4. 都不匹配（HTTP 层正常但体既非数组也没有 code）→ 解析失败。
 * 网络层失败（wx.request/wx.uploadFile 的 fail 回调）不在这里处理，由调用方分开说。
 */
function readEnvelope<T>(statusCode: number, body: unknown): T {
  if (statusCode < 200 || statusCode >= 300) {
    throw new ApiError(-1, `服务器返回 ${statusCode}`)
  }
  if (Array.isArray(body)) {
    return body as T
  }
  if (body && typeof body === 'object' && typeof (body as { code?: unknown }).code === 'number') {
    const env = body as { code: number; message?: string; data?: T }
    if (env.code === 0) {
      return env.data as T
    }
    if (env.code === 4010) {
      // 鉴权失败是 HTTP 200 + {code:4010}，不是 401——实测行为，见契约红线。
      setSession(null)
      wx.reLaunch({ url: '/pages/login/login' })
      throw new ApiError(4010, '请先登录')
    }
    throw new ApiError(env.code, env.message || '操作失败')
  }
  throw new ApiError(-1, '无法解析服务器响应')
}

function authHeader(): Record<string, string> {
  const session = getSession()
  return session ? { 'X-Session-Id': session } : {}
}

function request<T>(url: string, method: 'GET' | 'POST', data?: Record<string, unknown>): Promise<T> {
  return new Promise((resolve, reject) => {
    wx.request({
      url: BASE_URL + url,
      method,
      data,
      header: {
        ...authHeader(),
        ...(method === 'POST' ? { 'Content-Type': 'application/json' } : {}),
      },
      success: (res) => {
        try {
          resolve(readEnvelope<T>(res.statusCode, res.data))
        } catch (e) {
          reject(e)
        }
      },
      fail: () => {
        // 网络层失败要与业务失败分开说：用户看到「验证码错误」和看到
        // 「连不上服务器」会做完全不同的事。
        reject(new ApiError(-1, '连不上服务器，检查网络后重试'))
      },
    })
  })
}

// ---------- 登录 ----------

export function sendLoginCode(phone: string): Promise<void> {
  return request<void>('/api/auth/sms-login/send-code', 'POST', { phone })
}

export function verifyLoginCode(phone: string, code: string): Promise<LoginResult> {
  return request<LoginResult>('/api/auth/sms-login/verify', 'POST', { phone, code }).then((result) => {
    setSession(result.sessionId)
    setUser(result.user)
    return result
  })
}

/** 清会话 + 用户 + 已选项目，登出必须三个一起清，不然守门逻辑会判断错。 */
export function logout(): void {
  setSession(null)
  setUser(null)
  setSelectedProject(null)
}

// ---------- 项目与上传 ----------

/** 项目目录镜像，裸数组。空数组最常见的原因不是 bug：桌面端没开着，
 *  或桌面端还没用同一个手机号登录。 */
export function myProjects(): Promise<RelayProject[]> {
  return request<RelayProject[]>('/api/mobile/projects', 'GET')
}

/** 影像投递状态，裸数组。ids 为空直接返回 []，不发请求。 */
export function mediaStatus(ids: string[]): Promise<MediaStatus[]> {
  if (ids.length === 0) return Promise.resolve([])
  return request<MediaStatus[]>('/api/mobile/media/status', 'GET', { clientMediaIds: ids.join(',') })
}

/** 上传一件现场影像到中转区。幂等键是 clientMediaId，弱网重传不会产生重复件。 */
export function uploadMedia(opts: {
  filePath: string
  deviceId: string
  projectKey: string
  clientMediaId: string
  fileName: string
  mediaType: 'image' | 'video'
  capturedAt: string
  onProgress?: (percent: number) => void
}): Promise<void> {
  return new Promise((resolve, reject) => {
    const task = wx.uploadFile({
      url: BASE_URL + '/api/mobile/media',
      filePath: opts.filePath,
      name: 'file',
      header: authHeader(),
      formData: {
        deviceId: opts.deviceId,
        projectKey: opts.projectKey,
        clientMediaId: opts.clientMediaId,
        fileName: opts.fileName,
        mediaType: opts.mediaType,
        capturedAt: opts.capturedAt,
      },
      success: (res) => {
        // uploadFile 的 res.data 是字符串，先解出来再走同一套信封判读。
        try {
          let body: unknown
          try {
            body = JSON.parse(res.data)
          } catch {
            throw new ApiError(-1, '无法解析服务器响应')
          }
          readEnvelope<void>(res.statusCode, body)
          resolve()
        } catch (e) {
          reject(e)
        }
      },
      fail: () => {
        reject(new ApiError(-1, '连不上服务器，检查网络后重试'))
      },
    })
    if (opts.onProgress) {
      const onProgress = opts.onProgress
      task.onProgressUpdate((r) => onProgress(r.progress))
    }
  })
}

/** v4 UUID，小写。小程序没有 crypto.randomUUID 保证，用 Math.random 拼即可
 *  （只作幂等键，非安全用途）。 */
export function uuid(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    const v = c === 'x' ? r : (r & 0x3) | 0x8
    return v.toString(16)
  })
}
