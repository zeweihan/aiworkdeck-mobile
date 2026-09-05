import type { ApiErrorKind } from './api'

/**
 * 统一账户余额展示：整数分 → 带币种符号的金额，两位小数，不带千分位分隔符，
 * 不跟设备 locale 走。符号由响应里的 currency 决定，写死 ¥ 会让 USD 站点显示错币种。
 * 契约当前只定义了 CNY/USD 两种符号（contract/schema/billing.schema.json 的展示口径），
 * 三端逐字符对齐，用 contract/fixtures/billing.json 的 display 字段对拍
 * （dev-board#425 二轮复审 N7：iOS 之前用 NumberFormatter(.decimal) 带千分位且随设备语言走，
 * 与安卓/小程序的 toFixed(2) 对不上）。
 *
 * 纯函数，project.ts 与 tests/contract.test.ts 共用。
 */
export function formatMoney(cents: number, currency: 'CNY' | 'USD'): string {
  const symbol = currency === 'USD' ? '$' : '¥'
  return `${symbol}${(cents / 100).toFixed(2)}`
}

/**
 * 余额那一行该不该整行不渲染，一律按 Envelope.kind 分支，不匹配 message 措辞——
 * message 经服务端 LangText 在英文部署下会整条变英文（contract/schema/billing.schema.json UI 映射）。
 *
 * NOT_CONNECTED / DISABLED / REVIEW_ACCOUNT 是永远不会自己恢复的终态：分别对应
 * 「这个登录账号没有统一账户」「本部署没开这个功能（MOBILE_BILLING_BASE_URL 默认空，
 * 也就是四端一发版时的默认生产状态）」「审核演示账号一律关掉余额与充值入口」——
 * 渲染成「余额暂时读不到，稍后再试」等于给每个用户/审核员的设置页永久挂一行假瞬时错误
 * （dev-board#425 二轮复审 N2）。
 *
 * 其余一切（含 kind 缺席，即 code=1 但没带这个字段的非 billing 专有失败，例如缺
 * idempotencyKey 走了通用 handler）都是可能自己恢复的瞬时故障，返回 false，
 * 调用方显示 balance.unavailable。
 */
export function shouldHideBalanceRow(kind: ApiErrorKind | null): boolean {
  return kind === 'NOT_CONNECTED' || kind === 'DISABLED' || kind === 'REVIEW_ACCOUNT'
}
