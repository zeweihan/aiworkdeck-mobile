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

/** 余额行的渲染方案：行显不显、充值入口显不显、行上放哪句文案。 */
export interface BalanceRowPlan {
  showRow: boolean
  showRecharge: boolean
  /** 余额行的文案键；null 表示这一行不渲染文案（整行不渲染，或成功路径直接显示金额） */
  textKey: 'balance.notConnected' | 'balance.unavailable' | null
}

/**
 * 余额拉失败时该怎么渲染，唯一来源是 contract/schema/billing.schema.json 的 UI 映射
 * （一律按 kind 分支，不匹配 message 措辞）。
 *
 * canRecharge 就是本端有没有充值通道（contract/capabilities.json 的 recharge 非 false）：
 *  - 没有充值能力的端：完全照旧，NOT_CONNECTED / DISABLED / REVIEW_ACCOUNT 整行不渲染
 *    （shouldHideBalanceRow）；
 *  - 有充值能力的端（当前是小程序 virtual）只改 NOT_CONNECTED 一条：渲染余额行 +
 *    balance.notConnected + **充值入口照常可见**——触发 NOT_CONNECTED 的正是还没有统一
 *    账户、最该去充值把账户开出来的人，连入口一起藏掉就等于界面上找不到充值口
 *    （dev-board#535，第二期上线后实测反馈）。
 *
 * DISABLED / REVIEW_ACCOUNT 无论有没有充值能力都整行不渲染、入口一并收起：
 * 本部署没开通、审核演示账号，两种都不该出现充值。
 */
export function balanceRowForError(kind: ApiErrorKind | null, canRecharge: boolean): BalanceRowPlan {
  if (kind === 'DISABLED' || kind === 'REVIEW_ACCOUNT') {
    return { showRow: false, showRecharge: false, textKey: null }
  }
  if (kind === 'NOT_CONNECTED') {
    return canRecharge
      ? { showRow: true, showRecharge: true, textKey: 'balance.notConnected' }
      : { showRow: false, showRecharge: false, textKey: null }
  }
  // 其余（含 kind 缺席）都是可能自己恢复的瞬时故障：显示 balance.unavailable，
  // 充值入口保持可见——读不到余额不代表下不了单，下单失败自会按信封 message 提示。
  return { showRow: true, showRecharge: canRecharge, textKey: 'balance.unavailable' }
}
