# 安卓客户端（Kotlin + Jetpack Compose）设计

2026-09-02。dev-board：#400（安卓客户端立项），前置 #389（分发路径）、#392（四端契约）。
鸿蒙端保留在路线上（#391），在安卓之后开工，本 spec 不含鸿蒙。

维护者拍板（2026-09-02 21:06–21:16）：**完全对位 iOS 现有功能**；本机装 Android SDK；
minSdk 29；存相册默认开（随 iOS）；录像不分段；大陆版零 Google 依赖；持久化 JSON 文件不上 Room；
客户端加密与分块上传不强求；功能简单，务实实现，不过度设计。

## 0. 事实基线（来自 iOS 代码，以代码为准，不以旧设计文档为准）

- iOS「后台上传」实为前台 `URLSession` 请求，切后台只是让当前请求跑到超时。契约声明安卓
  `backgroundUpload: true`，安卓端要**真做到**：WorkManager 驱动，长上传挂前台通知。
- iOS `Backend.baseURL` 写死大陆站，国际版未真正切换（iOS 技术债）。安卓按构建变体分。
- 上传是单步 multipart，字段 `deviceId, projectKey, clientMediaId(小写 UUID), fileName, mediaType(image|video|audio), capturedAt(ISO8601)` + `file`；无分块、无客户端加密。
- 幂等键 `clientMediaId`；一次只传一条；失败退避首败 60 秒、逐次翻倍、封顶 15 分钟、成功复位。
- 队列页打开时每 20 秒轮询 `/api/mobile/media/status`；应用存活期间每 60 秒心跳 `autoKick`。
- 上传文件名：`现场影像-yyyyMMdd-HHmmss-{uuid 前 4 位}.{jpg|mov}`、`现场录音-…-….m4a`；安卓录像扩展名用 `mp4`。
- 本地目录 `FieldEvidence/{media,manifest}`，先写原件 → 流式 SHA-256 → 最后写 manifest（manifest 存在即记录完整）；启动清孤儿。
- 会话头 `X-Session-Id`；auth 类端点返回信封 `{code,message,data}`，`/api/mobile/*` 手机端接口是裸响应；未登录为 HTTP 200 + `{code:4010}`。
- 存相册只做「添加」，不读相册；音频不存相册。
- 契约已为安卓生成 `android/contract/src/main/kotlin/com/aiworkdeck/contract/{Tokens,Strings,States,Capabilities}.kt`（`T`、`ContractStrings.table`、`ContractStates.*`、`Transition`、`ContractCapabilities`）。

## 1. 决策记录

| # | 决策 | 理由 |
|---|---|---|
| A1 | 单应用模块 `:app` + 生成物模块 `:contract`，目录按 iOS 的 Services / Model / Features 对位 | 一人维护，可对照；多模块 Clean Architecture 是负担 |
| A2 | 领域层（状态机、分组、计数、删除警告）纯 Kotlin 无 Android 依赖 | JVM 跑契约夹具，不起模拟器 |
| A3 | 两个 productFlavor：`intl`（`com.aiworkdeck.mobile`，`https://addin.workdeck.ai`，默认邮箱登录）与 `cn`（`com.aiworkdeck.mobile.cn`，`https://addin.aiworkdeck.com`，默认短信登录） | 镜像 iOS 双 Bundle ID；修掉 iOS 写死地址的债 |
| A4 | **零 Google 依赖**：定位用系统 `LocationManager`，不接 GMS / Firebase / Play Integrity | 国产 ROM 无 GMS；契约 `deviceAttestation: false` |
| A5 | 持久化：与 iOS 同形状的 JSON manifest 文件，不上 Room | 「manifest 存在即完整」不变式直接继承，无 schema 迁移 |
| A6 | 上传：单飞协程 + Mutex，WorkManager 唯一任务驱动，前台通知 | 契约 `backgroundUpload: true` 要真兑现 |
| A7 | minSdk 29，compileSdk/targetSdk = 装 SDK 时最新稳定平台（金标联盟要求 Android 17） | 作用域存储起点；商店准入 |
| A8 | 存相册默认开、录像不分段、锁 zh-Hans | 随 iOS；国际版英文与 iOS 一样等词典覆盖（#398） |
| A9 | 不做加密/分块、不做设备证明、不做平板、仅竖屏 | 以 iOS 实际代码为准；用户明确不强求 |
| A10 | 签名与地址不进仓：keystore 路径/口令由 `local.properties` 或环境变量提供 | 总表 §0/§7.3 规矩 |

## 2. 工程

```
android/
  settings.gradle.kts        include(":app", ":contract")
  build.gradle.kts           版本目录 gradle/libs.versions.toml（AGP / Kotlin / Compose BOM / CameraX / WorkManager / OkHttp / kotlinx.serialization / security-crypto 全部锁版本）
  gradle/wrapper/            Gradle wrapper
  local.properties           sdk.dir、签名（gitignored）
  contract/build.gradle.kts  纯 Kotlin JVM 库（已有源码目录）
  app/
    build.gradle.kts         flavors intl/cn；BuildConfig.BASE_URL、DEFAULT_LOGIN；signingConfigs 读 local.properties
    src/main/AndroidManifest.xml
    src/main/kotlin/com/aiworkdeck/mobile/
      App.kt                 Application：WorkManager 初始化、心跳
      model/                 CaptureItem、CaptureManifest、TransferState（表驱动）、TransferTally、LibraryGrouping、RelayProject
      services/              Backend（OkHttp）、SessionStore、EvidenceStore、UploadQueue、UploadWorker、CameraService、AudioRecorderService、AlbumSaver、LocationStamper、Prefs
      design/                Tokens（T→Color/Dp）、L10n（tr）、Typography、Components（StatusDot、Glass、Pill）
      features/              auth/（Login、ProjectPicker）、home/（Home 取景器）、library/（Library、Viewer）、queue/（Queue）、settings/（Settings）
      AppModel.kt            根状态与路由：didRestore → 未登录 Login → 无项目 ProjectPicker → Home（+ 覆盖 Library/Queue/Settings）
    src/test/kotlin/         JVM：ContractFixturesTest（5 夹具）、TransferStateTest、LibraryGroupingTest、UploadQueueBackoffTest、BackendDecodeTest
  README.md                  构建、签名、模拟器、发版
```

## 3. 领域层（纯 Kotlin）

- `enum class TransferState(val raw: String)`：`waiting/uploading/uploaded/arrived/failed`；`fromRaw(s)` 经 `ContractStates.aliases`（`moving`→`uploading`）；`next(event, attempts)`、`recovered(attempts)`、`applyingStatus(delivered, waitingSeconds, expiresAt)` 与 iOS/小程序同语义（无规则→null；guard 不满足→原态；status 只对 uploaded 有意义）。
- `TransferPhase`：`uploading/staged/landed`，`ContractStates.phaseOf`；`caption = tr(phaseLabelKey)`；单件 `caption` 用 `stateTextKey`（短），`detail` 用 `stateDetailKey`。
- `TransferTally.of(items)`：`{uploading, failed, staged, landed, total}`，`failed ⊆ uploading`，只数当前项目。
- `LibraryGrouping`：按项目 `deviceId:key` 分组、自然日分段（本地时区，段头「M月d日 · N 件」）、`deleteWarningLevel(states) -> (level, n)`、`deleteWarning(items) = tr(deleteWarnKey[level], n)`。
- `CaptureManifest` 字段与 iOS 一致：`clientMediaId, sha256, capturedAt, serverReceivedAt?, latitude?, longitude?, horizontalAccuracy?, deviceModel, osVersion, appVersion, fromCamera, tsaToken?`；日期 ISO8601（写 `yyyy-MM-dd'T'HH:mm:ssXXX`，读宽容）。
- 所有用户可见文案走 `tr(key, vars)`（`ContractStrings.table[key]["zh-Hans"]`，缺键回显键名）；不在 Kotlin 里写取证主流程中文字面量（`check.mjs` 扫描 `android/app/src/**/*.kt`）。

## 4. 服务层

- **Backend**：OkHttp + kotlinx.serialization；`BuildConfig.BASE_URL`；所有请求加 `X-Session-Id`；`sendLoginCode/verifyLoginCode(sms)`、`sendMailLoginCode/verifyMailLoginCode`、`myProjects`、`upload(item, project, fileName, onProgress)`、`mediaStatus(ids)`、`mediaUsage`、`deleteAccount`；信封解码：`code==4010` 抛 `Unauthorized`（触发登出），`code!=0` 抛 `ApiError(message)`；裸响应直接解码。
- **SessionStore**：EncryptedSharedPreferences 存 `sessionId`。
- **EvidenceStore**：`filesDir/FieldEvidence/media/{uuid}.{jpg|mp4|m4a}`、`manifest/{uuid}.json`（`StoredRow{kind,state,progress,manifest,lastError?,savedToAlbum?,project?}`）；协程 `Mutex` 串行；`save()` 先移动原件再流式 SHA-256（1MB 块）再写 manifest；`loadAll/updateState/setProject/markSavedToAlbum/delete/sweepOrphans`；`android:allowBackup="false"`。
- **UploadQueue**：单飞（`Mutex.tryLock`），`kick()` 开头把滞留 `uploading` 件 `recovered()` 回 `waiting`；逐件用条目自带 `project`；成功 `http_2xx`→uploaded，失败→failed 记 `lastError`；退避 60s×2^n≤15min；`retryFailed()`；`checkDelivered()` 合并回执返回 `clientMediaId(lowercase)→expiresAt`；进度经 `StateFlow`。
- **UploadWorker**（WorkManager，唯一名 `upload`，`ExistingWorkPolicy.KEEP`，网络约束 CONNECTED，setExpedited + `setForeground` 通知「正在上传现场影像」）：调 `UploadQueue.kick()` 直到无 `waiting` 件；应用前台时 `AppModel` 每 60 秒也 `autoKick`。
- **CameraService**：CameraX `Preview + ImageCapture(CAPTURE_MODE_MAXIMIZE_QUALITY) + VideoCapture<Recorder>`；照片 JPEG 直接落文件不二次编码、不改 EXIF；录像 MP4 不限时；`fromCamera = true`。
- **AudioRecorderService**：`MediaRecorder` AAC 44.1kHz 单声道 64kbps，`.m4a`。
- **LocationStamper**：`LocationManager.getCurrentLocation(GPS_PROVIDER)`（API 30+）单次；拿不到不阻塞拍摄，坐标与精度可空。
- **AlbumSaver**：`MediaStore.Images/Video` 插入（`RELATIVE_PATH = Pictures/AI WorkDeck`），只添加；音频不存；`Prefs.saveToAlbum` 默认 true。
- **Prefs**：SharedPreferences：`saveToAlbum`、`selectedProject`（JSON）。

## 5. 界面（Compose，令牌全部来自 `T`）

| 屏 | 明暗 | 要点 |
|---|---|---|
| Login | 浅 | 手机号（cn 默认）/邮箱（intl 默认）两步验证码；6 位自动提交 |
| ProjectPicker | 浅 | `RelayProject` 列表、空态（`tr("empty.projects")`）、错误重试、退出登录 |
| Home（取景器） | **深** | 顶：项目名/归档路径「现场影像 / yyyy-MM-dd」/三桶计数（`tally.*`）/GPS 精度/设置；中：CameraX 预览 + 左下淡水印（时间/项目/坐标±精度，只叠加不烧录）；底：照片/录像/录音三档 + 大快门 + 最近缩略图 + 桌面端在线态；切后台停录落库 |
| Library | **深** | 项目菜单 + 自然日分段网格/列表、列数切换、多选删除三级警告（`delete.warn.*`）、进 Viewer；顶栏玻璃条 `glassBlur: runtime`（API 31+ `RenderEffect` 模糊，否则实色） |
| Viewer | 深 | 横滑同日条目；图片缩放；视频/音频 `ExoPlayer`（AndroidX Media3） |
| Queue | 浅 | 四段：失败/上传中/已暂存/已落盘（`queue.section.*`）；行：缩略图、状态点、进度、失败原因、SHA 前 12 位、重试；末行「其他项目还有 N 件未落盘」；20 秒轮询 |
| Settings | 浅 | 存相册开关、归档目标（切项目）、账号（服务器、退出、注销）、用量条、关于 |

根路由与 iOS 一致；Material3 仅作容器，配色/字号/间距全走 `T`；仅竖屏。

## 6. 权限与商店

`CAMERA`、`RECORD_AUDIO`、`ACCESS_FINE_LOCATION`、`POST_NOTIFICATIONS`（13+）、`FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC`、`INTERNET`。不申请存储读权限。注销账号入口在设置。

## 7. 测试与 CI

1. **第一件事**（根 CLAUDE.md 规则 6）：`ContractFixturesTest` 读 `contract/fixtures/*.json` 驱动 Kotlin 领域函数（tally / transitions / restore / status-merge / delete-warning）。
2. JVM 单测：状态机别名解码、退避序列、信封解码（含 4010）、文件名与日期格式、分组分段。
3. 界面：Compose Preview + 模拟器目视走查（AOSP 无 GMS 镜像验证 cn 路径）；首版不写 UI 自动化。
4. CI `.github/workflows/android.yml`：ubuntu、JDK 21、`./gradlew :app:testIntlDebugUnitTest :app:assembleIntlDebug :app:assembleCnDebug`。
5. 契约侧（走 contract-change）：`check.mjs` 内联扫描加 `android/app/src/main/**/*.kt`；实现后按实测校正 `capabilities.json` 的 android 值。

## 8. 本机环境（Task 0）

Homebrew `android-commandlinetools` → `sdkmanager` 装 `platform-tools`、最新稳定 `platforms;android-N`、对应 `build-tools`、`emulator`、`system-images;android-N;default;arm64-v8a`（AOSP 无 GMS）；`ANDROID_HOME` 写入 `~/.zshrc`；Gradle 用 wrapper。版本锁进 `gradle/libs.versions.toml`。

## 9. 发布形态（不在本 spec 实现，仅约束）

`cn` release 用 `aiworkdeck-cn.keystore` 签，`intl` 用 `aiworkdeck-intl.keystore`（总表 §7.3）；国内六家商店 + Google Play；不改包名与签名（已绑备案）。

## 10. 验收

- `./gradlew :app:testIntlDebugUnitTest` 绿，含 5 个契约夹具适配；`node contract/tools/check.mjs` 绿（扫到 android 源）。
- 模拟器（AOSP arm64）：登录 → 选项目 → 拍照/录像/录音各一 → 队列见上传中→已暂存 → 桌面端取件后 20 秒内翻已落盘 → 图集按日分组、删除三级警告 → 设置注销入口可达。
- 切到后台拍摄件仍上传完成（WorkManager 前台通知可见）。
- 大陆变体 APK 中无 `com.google.android.gms` 依赖（`./gradlew :app:dependencies --configuration cnReleaseRuntimeClasspath | grep -c gms` 为 0）。
