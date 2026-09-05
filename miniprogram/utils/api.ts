/**
 * 后端 API 封装 —— 全小程序唯一网络出口。
 *
 * 契约见 docs/specs/2026-08-20-miniprogram-real-api.md §2；
 * 响应判读语义照抄 iOS 端 ios/Sources/Services/Backend.swift（信封与裸数组两种形状、
 * 网络层失败与业务失败分开说）。鉴权用 X-Session-Id 请求头，与桌面端同门
 * （见 docs/specs/2026-08-20-project-sync-relay.md）。
 */

export const BASE_URL = 'https://addin.aiworkdeck.com'

/** 官网（Next.js 站点）。引流页换号走这里，与插件云后端不是一个服务。 */
export const WEB_BASE_URL = 'https://aiworkdeck.com'

/** Envelope.kind：机器可读判别位，contract/schema/billing.schema.json 的 $defs.kind 同一套取值。
 *  各端一律按 kind 分支，禁止匹配 message 措辞——message 经 LangText 在英文部署下会整条变英文。 */
export type ApiErrorKind =
  | 'DISABLED'
  | 'UNAVAILABLE'
  | 'NOT_CONNECTED'
  | 'NOT_FOUND'
  | 'REJECTED'
  | 'REVIEW_ACCOUNT'
  | 'ALREADY_PAID'
  | 'IDEMPOTENCY_CONFLICT'

/** 统一错误：code 是信封里的业务 code；网络层/HTTP 层失败固定为 -1。
 *  kind 是可选的机器可读判别位（缺席多半是非 billing 专有的失败，走通用 handler）；
 *  outTradeNo 仅 kind 为 ALREADY_PAID / IDEMPOTENCY_CONFLICT 时有值。 */
export class ApiError extends Error {
  code: number
  kind: ApiErrorKind | null
  outTradeNo: string | null
  constructor(code: number, message: string, kind: ApiErrorKind | null = null, outTradeNo: string | null = null) {
    super(message)
    this.code = code
    this.kind = kind
    this.outTradeNo = outTradeNo
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
  /** 中转区到期时刻（ISO 本地时间字符串），仅未投递件带；投递后不再有意义 */
  expiresAt?: string
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
 * 信封与裸数组共用一套判读，五条规则：
 * 1. HTTP 非 2xx → ApiError(-1, '服务器返回 N')。
 * 2. 体是数组 → 直接成功（裸数组端点：/projects、/media/status）。
 * 3. 体是对象且有数字 code：0 成功取 data；4010 清会话并跳登录后抛错；
 *    其他 code 原样抛错。
 * 4. 体是对象但没有数字 code：默认按解析失败处理——大多数端点的信封必然带数字
 *    code，一个没有 code 的对象体更可能是网关 interstitial / 代理注入 / 后端改了形状，
 *    不是合法响应。只有调用点显式传 `{ bare: true }`（当前只有 /billing/balance 这一条
 *    裸对象端点）才把它当成功直接返回。**不要为了让某个端点跑通而放宽这条判读**——
 *    放宽是全局的，会让 verifyLoginCode 把网关异常响应当登录成功、myProjects/mediaStatus
 *    把非数组交给 groupByDevice 变成运行时 TypeError（dev-board#425 二轮复审 N5）。
 * 5. 都不匹配（HTTP 层正常但体既非数组也非对象，如 null/字符串/数字）→ 解析失败。
 * 网络层失败（wx.request/wx.uploadFile 的 fail 回调）不在这里处理，由调用方分开说。
 *
 * export 仅为了 tests/contract.test.ts 拿 contract/fixtures/billing.json 的
 * envelope 夹具直接跑判读逻辑，不是给业务代码外部调用的公开 API。
 */
export function readEnvelope<T>(statusCode: number, body: unknown, opts: { bare?: boolean } = {}): T {
  if (statusCode < 200 || statusCode >= 300) {
    throw new ApiError(-1, `服务器返回 ${statusCode}`)
  }
  if (Array.isArray(body)) {
    return body as T
  }
  if (body && typeof body === 'object') {
    if (typeof (body as { code?: unknown }).code !== 'number') {
      if (opts.bare) return body as T
      throw new ApiError(-1, '无法解析服务器响应')
    }
    const env = body as { code: number; message?: string; data?: T; kind?: ApiErrorKind; outTradeNo?: string }
    if (env.code === 0) {
      return env.data as T
    }
    if (env.code === 4010) {
      // 鉴权失败是 HTTP 200 + {code:4010}，不是 401——实测行为，见契约红线。
      setSession(null)
      wx.reLaunch({ url: '/pages/login/login' })
      throw new ApiError(4010, '请先登录')
    }
    throw new ApiError(env.code, env.message || '操作失败', env.kind ?? null, env.outTradeNo ?? null)
  }
  throw new ApiError(-1, '无法解析服务器响应')
}

function authHeader(): Record<string, string> {
  const session = getSession()
  return session ? { 'X-Session-Id': session } : {}
}

function request<T>(
  url: string,
  method: 'GET' | 'POST',
  data?: Record<string, unknown>,
  opts: { bare?: boolean } = {},
): Promise<T> {
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
          resolve(readEnvelope<T>(res.statusCode, res.data, opts))
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

// ---------- 统一账户余额（dev-board#425/#429） ----------

export interface BillingBalance {
  balanceCents: number
  currency: 'CNY' | 'USD'
  plan: string | null
}

/**
 * 统一账户余额。裸对象成功；未登录/未关联/官网不可达等一律 Envelope(code 1) 走
 * readEnvelope 的信封分支抛错，绝不会用余额 0 冒充失败。本期只读余额，不放充值入口
 * （App Store 3.1.3 硬约束，站外充值行动号召会触发强制内购）。
 *
 * 唯一传 `{ bare: true }` 的调用点：裸对象响应没有数字 code，其余端点一律走默认的
 * 严格判读（见 readEnvelope 规则 4，dev-board#425 二轮复审 N5）。
 */
export function billingBalance(): Promise<BillingBalance> {
  return request<BillingBalance>('/api/mobile/billing/balance', 'GET', undefined, { bare: true })
}

// ---------- 引流页：一键手机号建号（dev-board#305） ----------

export interface WxStartResult {
  username: string
  displayName: string
  isNewUser: boolean
  /** 一次性登录票据（10 分钟有效），官网 /api/auth/wx-ticket 可换会话；手机号明文不回传 */
  ticket: string
}

/**
 * 把 button open-type="getPhoneNumber" 的 code 交给官网换号建号。
 *
 * 打的是官网（WEB_BASE_URL）不是插件云后端：响应是官网风格的裸 JSON
 * （成功含 user，失败含 error），不走 readEnvelope 那套信封判读。
 */
export function wxPhoneStart(code: string, ref: string): Promise<WxStartResult> {
  return new Promise((resolve, reject) => {
    wx.request({
      url: WEB_BASE_URL + '/api/auth/wx-phone',
      method: 'POST',
      data: { code, ref },
      header: { 'Content-Type': 'application/json' },
      success: (res) => {
        const body = (res.data ?? {}) as {
          user?: { username: string; displayName: string }
          isNewUser?: boolean
          ticket?: string
          error?: string
          message?: string
        }
        if (res.statusCode >= 200 && res.statusCode < 300 && body.user) {
          resolve({
            username: body.user.username,
            displayName: body.user.displayName,
            isNewUser: body.isNewUser === true,
            ticket: body.ticket || '',
          })
          return
        }
        // 官网端错误码翻译成用户能行动的话（文案红线：不出现「登录/未授权/请先」）
        const msg =
          body.error === 'invalid_wx_code'
            ? '授权凭证已失效，重新点一次按钮即可'
            : body.error === 'unsupported_region'
              ? body.message || '目前仅支持中国大陆手机号'
              : body.error === 'rate_limited'
                ? '操作太频繁，稍等一分钟再试'
                : '服务暂时不可用，稍后再试'
        reject(new ApiError(-1, msg))
      },
      fail: () => {
        reject(new ApiError(-1, '连不上服务器，检查网络后重试'))
      },
    })
  })
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
  mediaType: 'image' | 'video' | 'audio'
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
