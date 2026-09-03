import { RelayProject } from '../model/Capture'
import { ApiError } from '../model/Envelope'

/**
 * /api/mobile 的响应形状（`contract/api/mobile-v1.yaml`），字段与安卓 ApiTypes.kt 逐字一致。
 *
 * ArkTS 没有 kotlinx.serialization 那样的反射解码，`JSON.parse` 出来的是 `Object`，
 * 只能一个字段一个字段判类型再取——本文件下半段的 decodeXxx 就是这件事。
 * 少一个必填字段就当整条解不出（返回 null / 抛 ApiError），宁可报错也不要拿默认值冒充服务端数据。
 */

export interface AccountUser {
  id: number
  username: string
  displayName: string
  avatarUrl?: string
  role?: string
}

export interface LoginResult {
  sessionId: string
  isNewUser?: boolean
  mustBindPhone?: boolean
  user: AccountUser
}

export interface MediaStatus {
  clientMediaId: string
  delivered: boolean
  waitingSeconds: number
  expiresAt?: string
}

export interface MediaUsage {
  usedBytes: number
  quotaBytes: number
}

export interface UploadResult {
  code: number
  id: number
  clientMediaId: string
  delivered: boolean
}

// ---- 取值助手 ----

/** 解析结果是不是一个对象（数组不算）。 */
export function asRecord(v: Object | null | undefined): Record<string, Object> | null {
  if (v === undefined || v === null) return null
  if (v instanceof Array) return null
  if (typeof v !== 'object') return null
  return v as Record<string, Object>
}

export function asArray(v: Object | null | undefined): Object[] | null {
  if (v === undefined || v === null) return null
  if (!(v instanceof Array)) return null
  return v as Object[]
}

export function getString(o: Record<string, Object>, k: string): string | undefined {
  const v: Object | undefined = o[k]
  return typeof v === 'string' ? v as string : undefined
}

export function getNumber(o: Record<string, Object>, k: string): number | undefined {
  const v: Object | undefined = o[k]
  return typeof v === 'number' ? v as number : undefined
}

export function getBoolean(o: Record<string, Object>, k: string): boolean | undefined {
  const v: Object | undefined = o[k]
  return typeof v === 'boolean' ? v as boolean : undefined
}

// ---- 解码 ----

export function decodeRelayProject(o: Record<string, Object>): RelayProject | null {
  const deviceId: string | undefined = getString(o, 'deviceId')
  const key: string | undefined = getString(o, 'key')
  const name: string | undefined = getString(o, 'name')
  if (deviceId === undefined || key === undefined || name === undefined) return null
  const p: RelayProject = {
    deviceId: deviceId, deviceName: getString(o, 'deviceName'), key: key, name: name,
  }
  return p
}

export function decodeRelayProjects(v: Object | null): RelayProject[] {
  const arr: Object[] | null = asArray(v)
  if (arr === null) return []
  const out: RelayProject[] = []
  for (const raw of arr) {
    const o: Record<string, Object> | null = asRecord(raw)
    if (o === null) continue
    const p: RelayProject | null = decodeRelayProject(o)
    if (p !== null) out.push(p)
  }
  return out
}

export function decodeAccountUser(o: Record<string, Object>): AccountUser {
  const u: AccountUser = {
    id: getNumber(o, 'id') ?? 0,
    username: getString(o, 'username') ?? '',
    displayName: getString(o, 'displayName') ?? '',
    avatarUrl: getString(o, 'avatarUrl'),
    role: getString(o, 'role'),
  }
  return u
}

export function decodeLoginResult(data: Record<string, Object>): LoginResult {
  const sessionId: string | undefined = getString(data, 'sessionId')
  if (sessionId === undefined) throw new ApiError(1, 'login response without sessionId')
  const userObj: Record<string, Object> | null = asRecord(data['user'])
  const fallback: AccountUser = { id: 0, username: '', displayName: '' }
  const r: LoginResult = {
    sessionId: sessionId,
    isNewUser: getBoolean(data, 'isNewUser'),
    mustBindPhone: getBoolean(data, 'mustBindPhone'),
    user: userObj === null ? fallback : decodeAccountUser(userObj),
  }
  return r
}

export function decodeMediaStatuses(v: Object | null): MediaStatus[] {
  const arr: Object[] | null = asArray(v)
  if (arr === null) return []
  const out: MediaStatus[] = []
  for (const raw of arr) {
    const o: Record<string, Object> | null = asRecord(raw)
    if (o === null) continue
    const id: string | undefined = getString(o, 'clientMediaId')
    if (id === undefined) continue
    const s: MediaStatus = {
      clientMediaId: id,
      delivered: getBoolean(o, 'delivered') ?? false,
      waitingSeconds: getNumber(o, 'waitingSeconds') ?? 0,
      expiresAt: getString(o, 'expiresAt'),
    }
    out.push(s)
  }
  return out
}

export function decodeMediaUsage(v: Object | null): MediaUsage {
  const o: Record<string, Object> | null = asRecord(v)
  if (o === null) throw new ApiError(1, 'usage response is not an object')
  const u: MediaUsage = {
    usedBytes: getNumber(o, 'usedBytes') ?? 0,
    quotaBytes: getNumber(o, 'quotaBytes') ?? 0,
  }
  return u
}

/** 上传响应。服务端返回的是裸 UploadResult（含 code 0），缺字段时按调用方给的兜底补齐。 */
export function decodeUploadResult(o: Record<string, Object>, clientMediaId: string): UploadResult {
  const r: UploadResult = {
    code: getNumber(o, 'code') ?? 0,
    id: getNumber(o, 'id') ?? 0,
    clientMediaId: getString(o, 'clientMediaId') ?? clientMediaId,
    delivered: getBoolean(o, 'delivered') ?? false,
  }
  return r
}
