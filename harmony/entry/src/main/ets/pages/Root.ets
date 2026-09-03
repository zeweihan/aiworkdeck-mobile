import { T } from 'contract';
import { tr } from '../design/L10n';

// 临时首屏：证明 HAP 引到了 contract HAR 与 tr()。七屏在后续任务里替换这里。
@Entry
@Component
struct Root {
  build() {
    Column() {
      Text(tr('home.eyebrow'))
        .fontSize(T.Ty.title)
        .fontColor(T.L.fg)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(T.L.bg)
  }
}
