# 微信开放平台「移动应用」材料

来源：`docs/specs/2026-09-13-store-assets-design.md` §6。用户正在微信开放平台创建移动应用以
开通 APP 支付。

## 字段最终值

| 字段 | 值 / 文件 | 备注 |
|---|---|---|
| 应用名称 | `AI WorkDeck` | 与 App Store / 各商店一致 |
| 应用简介 | 律师做尽调、审计师盘点、工程师验厂验收，现场拍的照片、录像、录音，回到办公室还要一张张导出、重命名、归类。AI WorkDeck 移动端把这一步去掉：手机拍完，影像排队上传，直接落到你电脑上那个项目的「现场影像 / 日期」目录里。 | 从 `fastlane/metadata/zh-Hans/description.txt` 首段派生，139 字，字数上限**待核**（见下方「未验证项」）。表单若限 60 字以内，改用：`出现场的专业人士用的取证拍摄工具：拍完自动归档到电脑上的项目目录，影像带 SHA-256 摘要、时间与坐标。`（52 字） |
| 应用官网 | `https://www.aiworkdeck.com/zh` | |
| 移动应用图片（水印图） | `icon-28.png`，28×28 PNG，无 alpha 通道，1166 字节（≤ 300 KB） | 与商店图标同源（`docs/design/app-icon-1024-dark-green.png`） |
| 高清图 | `icon-108.png`，108×108 PNG，无 alpha 通道，4433 字节（≤ 300 KB） | 同上 |
| 应用商店 | 已在 App Store 上架（`com.aiworkdeck.mobile.cn`） | |
| App 备案号 | `京ICP备2024096997号-13A` | 与 ASC「App 信息」一致，见 `docs/RELEASE.md` §3.2 |
| 应用分类 | 商务 / 办公 | 以开放平台表单实际可选项为准，需用户在后台选择 |
| 应用运营流程图（主件） | `operation-flow-screens.png`，2400×1138 PNG，无 alpha，1,084,204 字节（1.03 MB） | **按微信官方定义做的真机截图串**：安卓大陆包在真机/模拟器上跑出来的 5 张界面截图，顺序 选择项目 → 现场拍摄 → 排队上传 → 按项目归档 → 桌面端落盘，图上带步骤编号与箭头。重出：`node scripts/store-shots/compose.mjs --flow` |
| 应用运营流程图（补充说明图） | `operation-flow.png`（源文件 `operation-flow.html`），1600×620 PNG，无 alpha | 概念性泳道框图（登录 → 选项目 → 拍摄 → 上传中转 → 桌面端落盘；充值：设置 → 充值 → 微信支付 → 余额入账）。表单只能传一张时传主件；若后台允许多图或需要文字说明，可作为补充 |
| 安卓平台 · 包名 | `com.aiworkdeck.mobile.cn` | 大陆包 |
| 安卓平台 · 签名 MD5 | `df:ea:3a:e5:53:7b:22:e1:f0:c0:87:83:52:36:0d:ed` | 由 `~/.aiworkdeck/android/aiworkdeck-cn.keystore`（alias `aiworkdeck-cn`，`keytool -list` 确认仅此一个别名）算出：`keytool -exportcert -alias aiworkdeck-cn -keystore aiworkdeck-cn.keystore -storepass <见 keystore-passwords.txt> \| openssl md5 -c`。证书 SHA-256 指纹为 `6F:1C:37:07:09:49:1C:C7:EC:BF:A2:D2:0B:79:68:81:7B:BD:EB:B6:D3:95:D0:DC:F1:43:FC:39:A5:F0:13:DF`，供交叉核对 |
| iOS 平台 · Bundle ID | `com.aiworkdeck.mobile.cn` | Universal Links 域名待定，本次只记字段 |

## 应用运营流程图：已按微信官方定义补做真机截图串

微信开放平台官方文档《创建移动应用》（`https://developers.weixin.qq.com/doc/oplatform/Mobile_App/guideline/create.html`，
查证日期 2026-09-13）原文对「App 运行流程图」的定义是：

> 应用的运行流程图指的是该 App 安装到手机后运行起来的界面截图，此时开发者可将多端应用的
> 安装包装在手机上进行截图即可。注意：如果运行的 App 截图和所申请的应用名称、类目、描述等
> 不一致，则审核会驳回。

也就是说官方要的是**真机界面截图的串联**，不是概念框图。最初产出的 `operation-flow.png`
是 HTML/CSS 画的泳道框图，不符合这条定义，**已按官方定义补做 `operation-flow-screens.png`**：

- 素材是安卓大陆包（`com.aiworkdeck.mobile.cn`）跑起来后截的 5 张真实界面，
  取自 `scripts/store-shots/raw/android/zh-Hans/`（08 / 01 / 03 / 04 / 07）。
- 横排 5 张，张与张之间有箭头，每张下方一行步骤文字：
  1 选择项目 → 2 现场拍摄 → 3 排队上传 → 4 按项目归档 → 5 桌面端落盘。
- 图左上角标了应用名 `AI WorkDeck`，与所申请的应用名称一致（官方那句「截图与应用名称、
  类目、描述不一致会驳回」指的就是这点）。
- 只做了圆角裁切，没有加设备边框，界面内容原样未改、未拉伸。
- 2400×1138 PNG，无 alpha，1.03 MB。

**提交时传 `operation-flow-screens.png` 为主件**；`operation-flow.png` 保留为补充说明图，
用于向审核解释「云端只做中转、桌面端确认后删除」这条链路和充值链路。

重出命令（截图换了、或流程文案要改时）：

```bash
node scripts/store-shots/compose.mjs --flow
```

步骤顺序与文案写在 `scripts/store-shots/compose.mjs` 的 `FLOW_STEPS`，
版式在 `scripts/store-shots/templates/flow.html`。

## 未验证项 / 待核

- **应用简介字数上限**：未在 `developers.weixin.qq.com` 的可抓取文本中找到具体数字（页面把
  尺寸/字数类规格放在内嵌图片里，无法用文本抓取工具提取）。规格文档 §6 只说「子代理核实字数
  上限（开放平台表单标注为准）」，本次核实未果，以开放平台实际表单的实时字数提示为准。上表
  139 字的文案供参考，提交前请在表单里试填一遍确认不超限。
- **开放平台后台该字段的实际提示文案**：未登录后台核对过。主件已按公开文档那段定义做成
  真机截图串；如果后台提示要求单张竖版、或限制图片数量/尺寸，以后台实时提示为准。
- **应用分类的可选项**：需用户登录后台查看实际下拉选项，本文件只填了大方向（商务/办公）。
- **Universal Links 域名**：本次未定，留空。

## 来源

- `docs/specs/2026-09-13-store-assets-design.md` §6
- `docs/RELEASE.md` §1、§3.2
- 微信开放平台文档《创建移动应用》：
  https://developers.weixin.qq.com/doc/oplatform/Mobile_App/guideline/create.html （查证日期 2026-09-13）
- 微信开放平台文档《移动应用基本资料填写说明》：
  https://developers.weixin.qq.com/doc/oplatform/Mobile_App/guideline/basic_info.html （查证日期 2026-09-13，图片内规格未能提取）
