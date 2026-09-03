import { Tk } from './Tokens'

/**
 * 共用小件。色只做点不做块、分区靠发丝线不靠卡片阴影——三端一致的克制
 * （docs/specs/2026-08-17-mobile-clients-design.md §5）。
 * 文案由调用方用 tr(key) 取好再传进来，这里不碰词典。
 */

/** 玻璃条的底色：深色面 + 0.72 不透明度，写成 ARGB 十六进制（0xB8 ≈ 0.72×255）。 */
const GLASS_BG: string = `#B8${Tk.D.surface.substring(1)}`

/** 状态点。颜色由调用方经 Tk.color(TransferStateOps.dotToken(state)) 解析。 */
@Component
export struct StatusDot {
  @Prop color: string = Tk.S.waiting
  /** 不叫 size：CustomComponent 已有同名通用属性方法，重名编不过 */
  @Prop dotSize: number = 5

  build() {
    Row()
      .width(this.dotSize)
      .height(this.dotSize)
      .borderRadius(this.dotSize / 2)
      .backgroundColor(this.color)
  }
}

/** 可点的小标签（项目切换、档位切换）。选中态只换前景与底色，不加边框。 */
@Component
export struct Pill {
  @Prop label: string = ''
  @Prop selected: boolean = false
  onTap: () => void = () => {}

  build() {
    Text(this.label)
      .fontSize(Tk.Ty.small)
      .fontColor(this.selected ? Tk.D.fg : Tk.L.fgMuted)
      .backgroundColor(this.selected ? Tk.L.accent : Tk.L.sunken)
      .padding({
        left: Tk.Sp.s3, right: Tk.Sp.s3, top: Tk.Sp.s2, bottom: Tk.Sp.s2
      })
      .borderRadius(Tk.touchMin / 2)
      .onClick(() => {
        this.onTap()
      })
  }
}

/**
 * 玻璃条：压在影像上的半透明深色带（查看器的顶栏与底座）。
 * 契约把 glassBlur 标为真，鸿蒙有真模糊：.backdropBlur 糊的是它下面已经画好的内容，
 * 条上的文字不受影响——这正是安卓做不到而这里能做的那一档。
 */
@Component
export struct GlassBar {
  @BuilderParam content: () => void = this.placeholder

  @Builder
  placeholder() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .backgroundColor(GLASS_BG)
    .backdropBlur(20)
  }
}

/** 主按钮。单一强调色不分明暗——accent 只在浅色组给了值，取景器上的按钮也用它。 */
@Component
export struct PrimaryButton {
  @Prop label: string = ''
  /** 不叫 enabled：与 CustomComponent 的通用属性方法重名 */
  @Prop isEnabled: boolean = true
  onTap: () => void = () => {}

  build() {
    Text(this.label)
      .fontSize(Tk.Ty.body)
      .fontColor(Tk.D.fg)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(Tk.touchMin)
      .backgroundColor(Tk.L.accent)
      .opacity(this.isEnabled ? 1 : 0.4)
      .borderRadius(Tk.touchMin / 2)
      .enabled(this.isEnabled)
      .onClick(() => {
        this.onTap()
      })
  }
}
