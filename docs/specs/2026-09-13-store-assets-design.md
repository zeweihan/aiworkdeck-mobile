# 商店素材翻新：定位、截图叙事、文案、微信开放平台材料

dev-board 主卡 #617（iOS #618 / 安卓 #619 / 鸿蒙 #620）。2026-09-13。

## 1. 定位

一句话：**出现场的专业人士，拍完就归档到项目里。**

主线对「律师 / 尽调团队」说话，第二层带到审计盘点、验厂、工程验收、保险查勘。
不用「文档工作者」这个抽象词做标题，它只出现在描述正文的收束段。

三个必须传递的信任点（顺序固定）：
1. 拍完直接落到电脑上那个项目的目录，回办公室不用再整理；
2. 每一张影像在写入时算 SHA-256，连同时间、GPS、设备一起归档，摘要在设备上生成；
3. 工作影像与私人照片分开管理、云端只做中转、桌面端确认落盘后立即删除。

## 2. 截图叙事（三端同一套 8 张）

| # | 屏 | 中文主标题 | 中文副题 | English headline | English subline |
|---|---|---|---|---|---|
| 1 | 首页取景（项目名 + 归档路径 + GPS 精度 + 桌面端在线） | 现场拍的，直接落到项目目录 | 手机拍完，照片就在电脑上那个项目的「现场影像 / 日期」里 | Shot on site, filed in the project | Every capture lands in that project's Site Media / date folder on your computer |
| 2 | 首页取景，「SHA-256 · GPS · 时间戳」徽标区放大 | 每一张都有可核验的指纹 | 写入的同时计算 SHA-256，连同时间、坐标、设备一起归档 | Every capture carries a verifiable fingerprint | SHA-256 computed as it is written, filed with time, location and device |
| 3 | 上传队列（上传中 / 已暂存 / 已落盘三段） | 弱网中断不丢件 | 退出应用、断网重连，回来接着传 | Nothing is lost to a dropped connection | Quit the app or lose signal; transfers resume when you are back |
| 4 | 图集按项目 / 按日 | 回办公室不用再一张张整理 | 按项目、按日期自动分好，和电脑上的目录一一对应 | No more sorting when you are back at your desk | Grouped by project and by day, mirroring the folders on your computer |
| 5 | 查看器（含拍摄时间 / 坐标 / 设备 / 摘要） | 拍摄信息随图归档 | 拍摄时间与 SHA-256 摘要随图可查，坐标与设备信息写进归档信息一并落盘 | Capture details travel with the file | Capture time and SHA-256 digest at a glance; coordinates and device details travel with the file |
| 6 | 录音（iOS 含灵动岛；安卓 / 鸿蒙常驻通知） | 谈话记录切后台继续录 | 来电、切应用都不中断，中断后自动续录 | Recording keeps going in the background | Calls and app switches don't stop it; it resumes on its own |
| 7 | 设置页（云端中转用量 + 本地原图说明） | 云端只做中转 | 桌面端确认落盘后立即删除中转副本，本地原图不会被自动删除 | The cloud is only a relay | Deleted the moment your desktop confirms; local originals are never auto-deleted |
| 8 | 项目选择器（多个在办项目） | 一部手机，服务所有在办项目 | 切换项目，影像各归各的目录 | One phone, every matter you are on | Switch projects; each capture files itself into the right folder |

安卓第 6 张副题改为「常驻通知里看得见时长，切应用不中断」/ "Duration stays in the notification; switching apps doesn't stop it"；鸿蒙的系统长时任务通知不带时长，改为「切到后台、锁屏也继续录，来电中断后自动续录」/ "Keeps recording in the background and picks up again after a call"。

## 3. 视觉系统

- 底色：取 `docs/design/app-icon-1024-dark-green.png` 的深绿底色为主色，页面用同色系深色渐变（上浅下深），不用纯黑。
- 标题：PingFang SC / HarmonyOS Sans SC 粗体，中文主标题 2 行内；英文 Inter / SF Pro 粗体。副题一行，浅色 70% 不透明。
- 设备：iOS 用 iPhone 17 Pro Max 圆角与灵动岛的简化边框（不用 Apple 官方 bezel 素材）；安卓 / 鸿蒙用通用圆角边框加打孔摄像头。截图占画面下部约 72%，顶部留标题。
- 影像素材：`scripts/store-shots/assets/scenes/` 下 8 张现场照片，内容限定：档案室 / 合同与卷宗特写 / 会议室尽调现场 / 工厂车间 / 工地 / 仓库盘点 / 办公楼外立面 / 设备铭牌。**不出现可辨识的人脸、真实公司名与真实门牌。**
- 演示项目名统一：`华创科技 A 轮尽调`（主）、`恒达制造 验厂`、`南山路 12 号 工程验收`（项目选择器用）。归档日期 2026-09-12。

## 4. 各商店尺寸与落地目录

| 商店 | 尺寸 | 落地 | 上传方式 |
|---|---|---|---|
| App Store iPhone 6.9 吋 | 1320×2868 PNG，zh-Hans 与 en-US 各 8 张 | `fastlane/screenshots/<locale>/01..08.png` | `scripts/asc-listing.py screenshots`（已支持） |
| Google Play / 国内六家（安卓） | 1080×2400 PNG 8 张；宣传图 1024×500 zh/en | `android/store/screenshots/phone-1080x2400/`、`android/store/feature-graphic-*.png` | 用户在各商店后台上传 |
| 华为 AGC（鸿蒙） | 以 AGC 当前规格为准（子代理核实并写进 `harmony/store/README.md`） | `harmony/store/screenshots/` | 用户在 AGC 上传 |
| 微信开放平台移动应用 | 见 §6 | `android/store/wechat-open/` | 用户在开放平台填 |

原始屏（未合成）落 `scripts/store-shots/raw/<end>/<locale>/NN.png`，合成脚本从原始屏 + `captions.json` 出全部尺寸。

## 5. 文案

### 5.1 App Store（zh-Hans 主语言）

- 名称：`AI WorkDeck`（不变）
- 副标题（30 字内）：`出现场，拍完就归档到项目里`
- 推广文本（170 字内）：`律师、审计师、验厂工程师的现场取证入口：手机拍完，影像连同 SHA-256 摘要、时间、坐标直接落到电脑上那个项目的目录。`
- 关键词（100 字节内，逗号分隔，去掉与名称重复的词）：`尽调,取证,现场,归档,存证,律师,审计,验厂,验收,证据,影像,项目,同步,勘验`
- 描述：以下为母本，子代理定稿时保留段落顺序与全部事实，可润句，不许新增产品没有的能力。

```
出现场的专业人士，拍完就归档到项目里。

律师做尽调、审计师盘点、工程师验厂验收，现场拍的照片、录像、录音，回到办公室还要一张张导出、重命名、归类。AI WorkDeck 移动端把这一步去掉：手机拍完，影像排队上传，直接落到你电脑上那个项目的「现场影像 / 日期」目录里，和桌面端的项目文件放在一起。

每一张都有可核验的指纹
影像写入的同时计算 SHA-256 摘要，连同拍摄时间、GPS 坐标与定位精度、设备型号、系统版本一起写进归档信息。摘要在设备上生成，不依赖网络。

工作影像与私人照片分开
影像保存在本应用内的独立图集里，按项目、按日期归档，不与私人照片混在一起。是否同时存入系统相册，在设置里一键切换。

弱网中断不丢件
上传中、已暂存、已落盘三种状态分开显示。断网、退出应用都不会丢件，回来接着传。

云端只做中转
桌面端确认落盘后立即删除中转副本；7 天有效期只是兜底，不是主要机制。

照片、录像、录音，一个取景框
三种取证形式在同一界面切换，归档到同一个项目目录。录音切到后台继续录，来电中断后自动续录。

一部手机，服务所有在办项目
切换项目，影像各归各的目录。

适合谁
律师事务所的尽调与勘验、会计师事务所的审计盘点、供应链验厂、工程验收、保险查勘，以及所有以文档为工作对象、需要把现场带回项目里的人。

需要 AI WorkDeck 账号，并与 AI WorkDeck 桌面端配合使用。
```

### 5.2 App Store（en-US）

按 5.1 意译，不逐句直译；副标题 `Field capture, filed for you` 保留；末段保留 "The app interface is currently in Simplified Chinese only."。

### 5.3 安卓（`android/store/listing/`）

字段映射与上限见该目录 README，从 5.1 / 5.2 派生；国内六家的「一句话简介」用副标题。

### 5.4 鸿蒙（`harmony/store/listing/`，新建）

AGC 字段：应用名称、应用简介（一句话）、应用介绍、更新说明。从 5.1 派生，子代理核实各字段上限。

### 5.5 微信小程序（公众平台「小程序简介」，用户手填）

一句话（≤ 120 字）：`现场取证拍摄伴侣：拍完自动归档到电脑上的项目目录，影像带 SHA-256 摘要、时间与坐标。需配合 AI WorkDeck 桌面端使用。`

## 6. 微信开放平台「移动应用」材料（`android/store/wechat-open/`）

用户正在开放平台创建移动应用以开通 APP 支付（安卓大陆包 `com.aiworkdeck.mobile.cn`，iOS `com.aiworkdeck.mobile.cn`）。产出：

| 字段 | 值 / 文件 | 要求 |
|---|---|---|
| 应用名称 | `AI WorkDeck` | 与商店一致 |
| 应用简介 | 从 5.1 首段派生，子代理核实字数上限（开放平台表单标注为准） | |
| 应用官网 | `https://www.aiworkdeck.com/zh` | |
| 移动应用图片（水印图） | `wechat-open/icon-28.png` | 28×28 PNG ≤ 300 KB，与商店图标一致 |
| 高清图 | `wechat-open/icon-108.png` | 108×108 PNG ≤ 300 KB，与商店图标一致 |
| 应用商店 | 已在至少一个商店发布（App Store 已上架） | |
| App 备案号 | `京ICP备2024096997号-13A` | 与 ASC「App 信息」一致 |
| 应用分类 | 商务 / 办公（以表单可选项为准，用户选） | |
| 应用运营流程图 | `wechat-open/operation-flow.png` | 登录 → 选项目 → 拍摄 → 上传中转 → 桌面端落盘；充值：设置 → 充值 → 微信支付 → 余额入账。1600 宽左右 PNG，中文 |
| 安卓平台 | 包名 `com.aiworkdeck.mobile.cn`；签名 MD5 由 `~/.aiworkdeck/android/` 的大陆 keystore 算出（子代理算出后只写进 wechat-open/README.md，不进对话） | |
| iOS 平台 | Bundle ID `com.aiworkdeck.mobile.cn`；Universal Links 域名待定（本次只记字段） | |

图标源：`docs/design/app-icon-1024-dark-green.png`（与 ASC 1024 图标同源）。

## 7. 管线（`scripts/store-shots/`）

```
scripts/store-shots/
  assets/scenes/          现场照片（可整目录替换）
  captions.json           §2 的表，含 locale 与端差异
  seed/                   各端灌数据用的 manifest 模板
  capture-ios.sh          simctl 启动带 -AWDScreenshotMode 的 Debug 包并截 8 屏
  capture-android.sh      emulator + run-as 灌数据 + screencap
  capture-harmony.sh      hdc + awdSeed + snapshot_display
  compose.mjs             raw + captions → 各商店尺寸（Playwright 渲染 HTML 模板）
  templates/frame.html    标题 + 设备边框 + 截图
```

`node scripts/store-shots/compose.mjs --end ios --locale zh-Hans` 一条命令出一套。合成用 Playwright Chromium（本机已缓存 chromium）。

## 8. 验收

- 每端 8 张原始屏与合成图路径进汇报；合成图逐张过目（标题不截断、截图不变形、状态色正确）。
- 尺寸用 `sips -g pixelWidth -g pixelHeight` 核对，PNG 无 alpha（App Store 拒收带透明通道的截图）。
- 文案字数用脚本核对并写进各 listing README。
- ASC 上传后用 `asc-listing.py status` 看两语言截图组均为 1、每组 8 张。
