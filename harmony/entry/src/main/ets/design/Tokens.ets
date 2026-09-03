import { T, TokensD, TokensL, TokensMotion, TokensS, TokensSp, TokensTy } from 'contract'

/**
 * 设计令牌的取用入口。颜色是 CSS 字符串（ArkUI 的 ResourceColor 直接吃），
 * 间距单位 vp、字号单位 fp，数值直接来自契约，不在端上另起一套。
 */
export class Tk {
  static readonly L: TokensL = T.L
  static readonly D: TokensD = T.D
  static readonly S: TokensS = T.S
  static readonly Sp: TokensSp = T.Sp
  static readonly Ty: TokensTy = T.Ty
  static readonly Motion: TokensMotion = T.Motion
  static readonly touchMin: number = T.touchMin

  /**
   * 令牌名解析成颜色。状态点的令牌名（'S.waiting' 等）由 ContractStates 给出，
   * 端上不写死状态到颜色的对应关系；令牌表改了这里会抛，而不是默默给错颜色。
   *
   * `onDark` 是「这个点画在深色面上」：契约给三个状态各备了一份 `*OnDark`，
   * 浅色面的那份放到影像缩略图上对比度不够，「已暂存 / 已落盘」在格子里分不清。
   * 与安卓 `design/Components.kt` 的 `dotColor(token, onDark)` 同形。
   * `failed` 没有 onDark 变体（红在两种面上都够），照原样返回。
   */
  static color(token: string, onDark: boolean = false): string {
    switch (token) {
      case 'S.waiting': return onDark ? T.S.waitingOnDark : T.S.waiting
      case 'S.moving': return onDark ? T.S.movingOnDark : T.S.moving
      case 'S.arrived': return onDark ? T.S.arrivedOnDark : T.S.arrived
      case 'S.failed': return T.S.failed
      case 'S.waitingOnDark': return T.S.waitingOnDark
      case 'S.movingOnDark': return T.S.movingOnDark
      case 'S.arrivedOnDark': return T.S.arrivedOnDark
      default: throw new Error(`unknown color token: ${token}`)
    }
  }
}
