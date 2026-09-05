/**
 * 全站信封的纯解析部分（Backend 用，不碰网络）。code 0 成功；4010 未登录；其他为业务错误。
 * 裸数组 / 无 code 的响应不进这里的判定。
 */

export class ApiError extends Error {
  code: number

  constructor(code: number, message: string) {
    super(message)
    this.code = code
  }
}

export class Unauthorized extends Error {
  constructor() {
    super('unauthorized')
  }
}

/** ArkTS 里 Record 的值是 Object，取出来要显式判类型再用。 */
export function checkEnvelope(obj: Record<string, Object>): void {
  const raw: Object | undefined = obj['code']
  if (raw === undefined || raw === null) return
  if (typeof raw !== 'number') return
  const code: number = raw as number
  if (code === 4010) throw new Unauthorized()
  if (code === 0) return
  const rawMessage: Object | undefined = obj['message']
  const message: string = typeof rawMessage === 'string' ? rawMessage as string : `code ${code}`
  throw new ApiError(code, message)
}
