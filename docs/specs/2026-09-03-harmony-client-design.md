# 鸿蒙客户端（HarmonyOS NEXT，ArkTS）设计

2026-09-03。dev-board：[#391](https://github.com/zeweihan/dev-board/issues/391)（鸿蒙客户端首版）、
[#407](https://github.com/zeweihan/dev-board/issues/407)（录音后台续录 + 实况窗）。
前置：#392（四端契约）、#400（安卓客户端）、#404–#406（三端录音后台续录）。

**本 spec 沿用安卓设计** `docs/specs/2026-09-02-android-client-design.md` 的功能范围、领域层语义、
服务层职责与七屏界面，**只写鸿蒙的差异**。安卓 spec 里没被本文覆盖的条目，鸿蒙照抄。
录音后台续录的四端总设计见 `docs/specs/2026-09-03-background-recording-design.md`。

维护者既有拍板（沿用）：完全对位 iOS/安卓现有功能；持久化 JSON 文件不上数据库；
不做客户端加密与分块；功能简单务实，不过度设计。

## 0. 事实基线（2026-09-03 本机实测 + SDK d.ts 核对）

| 项 | 事实 |
|---|---|
| IDE / SDK | DevEco Studio 26.0.0（`/Applications/DevEco-Studio.app`），HarmonyOS SDK **API 26**（`sdk/default/openharmony` + `hms`，版本 26.0.0.105），hvigor / hvigor-ohos-plugin 6.26.4，ohpm、hdc、内置 node 24 齐全 |
| 模拟器 | 模拟器程序在 IDE 内；已定义 4 台实例（Pura 90 Pro / Mate X7 / MatePad Pro 13 / MateBook Pro，均 API 26），但**系统镜像未下载**（`~/Library/Huawei/Sdk` 不存在，`Emulator -imageList` 显示 phone 镜像 `downloaded=false`）。下载镜像与接受模拟器许可是用户动作 |
| 调试签名 | `~/.ohos` 不存在 = 从未做过 DevEco 自动签名。HarmonyOS 模拟器/真机只装华为签发的调试签名 HAP，自动签名要在 DevEco 登录华为开发者账号，是用户动作 |
| 发布签名 | `~/.aiworkdeck/harmony/`：`aiworkdeck-harmony.p12`（ECC P-256）+ `material/` + AGC 发布证书 `.cer`（至 2029-09-03）+ CSR；发布 Profile `.p7b` 待建。包名 **`com.aiworkdeck.mobile.huawei`**（总表 §7.4.1）。ICP 备案变更待用户几天后提交，不阻塞开发 |
| Live View Kit | `@hms.core.liveview.liveViewManager` 本地实况窗 API 存在（`startLiveView/updateLiveView/stopLiveView`，`timer` 自走计时），但 `event` 必须是固定场景之一（TAXI/DELIVERY/…/TIMER/PROGRESS…），**每个场景都要在 AGC 申请实况窗权限**，未获批调用抛 `1003500005 The right of liveView is not enabled`。录音不是列出的场景，最接近的是 TIMER。能否申请到取决于华为审核 |
| 长时任务 | `@ohos.resourceschedule.backgroundTaskManager.startBackgroundRunning(context, BackgroundMode.AUDIO_RECORDING, wantAgent)`，权限 `ohos.permission.KEEP_BACKGROUND_RUNNING`，`module.json5` `backgroundModes: ["audioRecording"]`。长时任务运行期间**系统自己挂常驻通知**（应用名 + 正在录音，点击走 wantAgent 回应用），应用不必再发通知；应用自建通知的操作按钮（actionButtons）是系统接口，三方应用不可用 |
| AVRecorder | 纯音频：`audioSourceType: AUDIO_SOURCE_TYPE_MIC`，`profile: { audioCodec: AUDIO_AAC, fileFormat: CFT_MPEG_4A, audioSampleRate: 44100, audioChannels: 1, audioBitrate: 64000 }`，输出 `.m4a`；支持 `pause()/resume()` 续写同一文件。**API 26 的 `AVRecorder` 没有 `audioInterrupt` 事件**（那是 `AVPlayer` 的，实施时核对 d.ts 发现）：焦点被抢时录音机被置 `paused`（`on('stateChange')`），或报 `on('error')` 码 `AVERR_AUDIO_INTERRUPTED`；焦点还回来通常自己回到 `started` |
| 存相册 | `ohos.permission.WRITE_IMAGEVIDEO` 是受限权限（须 AGC 申请 ACL）。无该权限时只能 `photoAccessHelper.showAssetsCreationDialog`（系统确认弹窗）或 `SaveButton` 安全控件（用户点它才授临时权） |
| 上传 | `@ohos.request` `request.agent` 任务 `mode: BACKGROUND` 切后台后由系统继续传，可兑现契约 `backgroundUpload: true`；multipart 经 `data: [{name, value}]`（文件项 `{path, filename, mimeType}`），头经 `headers`，进度 `on('progress')`，完成 `on('completed')` / `on('failed')` |
| 契约生成物 | `harmony/contract/src/main/ets/*.ets` 用了 `as const` 与无类型对象字面量，**ArkTS 严格模式编不过**（arkts-no-as-const、arkts-no-untyped-obj-literals）。按交接记录改 `contract/tools/lib.mjs` 的 ArkTS 渲染器，不手改生成物 |
| 服务端 | 单站大陆 `https://addin.aiworkdeck.com`（华为应用市场只发大陆）；接口形状 `contract/api/mobile-v1.yaml`，与安卓 `Backend.kt` 完全一致 |

## 1. 决策记录

| # | 决策 | 理由 |
|---|---|---|
| H1 | 单工程 `harmony/`：`entry`（HAP）+ `contract`（HAR，生成物）；`entry/src/main/ets/` 下按 `model / services / design / pages` 对位安卓 | 与安卓、iOS 同一套目录心智；契约设计已把生成物钉在 `harmony/contract/src/main/ets` |
| H2 | 领域层（状态机、三桶计数、分组、删除警告、文件名、ISO 时间、RecordingClock）写成**不引任何 `@ohos/@kit` 的 `.ets`**，夹具测试放仓库根 `tests/harmony/*.test.ts`，由现有 `npm test`（Node type-stripping）驱动；`scripts/node-ts-resolve.mjs` 扩一段：`.ets` 用 `typescript.transpileModule` 转译，裸说明符 `contract` 映射到 `harmony/contract/Index.ets` | GitHub runner 装不了 DevEco，Node 跑夹具是唯一能进 CI 的办法；ArkTS 是 TS 子集，纯逻辑文件 Node 能跑。DevEco 本地测试（hypium）首版不建 |
| H3 | 单产品、单 product `default`；大陆站；登录默认短信、邮箱可切 | 华为市场只发大陆；不复制安卓的 intl/cn 两变体 |
| H4 | `compatibleSdkVersion` 从 **5.0.0(12)** 起（HarmonyOS NEXT 首批公开设备），`targetSdkVersion` = 本机 SDK；高于 12 的 API 用版本判断降级或不用。**字符串写法以 hvigor 实际接受为准**，脚手架任务第一件事就是把它编过 | 尽可能覆盖存量机；不为未知的 API 差异空想 |
| H5 | 持久化：与 iOS/安卓同形状的 JSON manifest 文件（`filesDir/FieldEvidence/{media,manifest}`），`@ohos.file.fs`；哈希 `@ohos.file.hash.hash(path, 'sha256')`（系统流式算，不读进内存）；串行用一把 Promise 链锁 | 「manifest 存在即完整」不变式直接继承；不上关系型数据库 |
| H6 | 上传走 `request.agent` 后台任务，单飞；**不依赖任务回调做持久化真源**——进程被杀时的在途件按契约 `app_launch` 回拨 `waiting` 重传，幂等键 `clientMediaId` 保证服务端不重复 | 系统级后台续传是鸿蒙兑现 `backgroundUpload: true` 的正道；回拨 + 幂等让「回调丢了」不成为问题 |
| H7 | 录音 = AVRecorder + AUDIO_RECORDING 长时任务 + 中断自动续录；计时由 `RecordingClock`（纯逻辑，与 iOS 同名同语义）派生；常驻展示**首版用长时任务的系统通知**；实况窗**留卡**，待用户在 AGC 申请 TIMER 场景权限后另做 | 规格允许「申请不下来就只做长时任务 + 系统通知」；申请是用户在 AGC 的动作，本轮不等它 |
| H8 | 存相册开关**默认关**；打开后每件拍照/录像完成时走 `showAssetsCreationDialog` 系统确认；音频不存 | 无 WRITE_IMAGEVIDEO 权限时没有静默写相册的路；每件弹窗打断取证节奏，所以不能默认开。日后 AGC 批了受限权限再改静默 |
| H9 | 会话 `sessionId` 存 Asset Store Kit（`@kit.AssetStoreKit`）；偏好（存相册开关、选中项目 JSON）存 `@ohos.data.preferences` | 凭据放系统密钥库，与安卓 EncryptedSharedPreferences 对位 |
| H10 | 定位 `geoLocationManager.getCurrentLocation` 单次，权限 `APPROXIMATELY_LOCATION` + `LOCATION`；拿不到不阻塞拍摄 | 与安卓 LocationStamper 一致 |
| H11 | 签名不进仓：`build-profile.json5` 的 `signingConfigs` 保持空数组；DevEco 自动签名写进去的块**不提交**（README 写明，`check.mjs` 扫到 `storePassword` 即红） | 总表 §0 规矩；调试签名材料是机器本地的 |
| H12 | 不做：客户端加密/分块、设备证明、平板与折叠展开态适配（仅竖屏手机）、英文 UI、代码混淆、实况窗（留卡）、录像后台续录 | 与安卓 A9 一致；实况窗见 H7 |

## 2. 工程

```
harmony/
  build-profile.json5        app: signingConfigs []，products [default]，modules [entry, contract]
  hvigorfile.ts              appTasks
  hvigor/hvigor-config.json5 modelVersion 与本机 hvigor 一致
  oh-package.json5           devDependencies @ohos/hypium（模板自带，暂不用）
  AppScope/app.json5         bundleName com.aiworkdeck.mobile.huawei，versionCode/versionName，icon，label
  AppScope/resources/        应用名、图标（源 = iOS Icon-1024.png，脚本另卡）
  code-linter.json5          模板默认
  .gitignore                 /oh_modules /.hvigor /.idea **/build /local.properties .preview .test
  contract/                  HAR（生成物，文件头 GENERATED）
    oh-package.json5 / build-profile.json5 / hvigorfile.ts / Index.ets / src/main/module.json5
    src/main/ets/{Tokens,Strings,States,Capabilities}.ets
  entry/
    oh-package.json5         dependencies { "contract": "file:../contract" }
    build-profile.json5      apiType stageMode；targets [default]
    hvigorfile.ts            hapTasks
    src/main/module.json5    见 §6
    src/main/resources/      base/element（app 名、颜色）、base/media（图标）、base/profile/main_pages.json
    src/main/ets/
      entryability/EntryAbility.ets   loadContent('pages/Root')；onForeground 触发心跳
      AppModel.ets             根状态（@ObservedV2 / AppStorage）：didRestore → 未登录 Login → 无项目 ProjectPicker → Home（+ Library/Queue/Settings 页）
      model/                   Capture.ets（MediaKind、CaptureManifest、RelayProject、StoredRow、CaptureItem）、TransferState.ets、TransferTally.ets、LibraryGrouping.ets、UploadNaming.ets、IsoTime.ets、RecordingClock.ets、AppModelLogic.ets（otherPendingCount、isDesktopOnline）
      services/                Backend.ets（@ohos.net.http）、SessionStore.ets、EvidenceStore.ets、UploadQueue.ets、Uploader.ets（request.agent）、CameraService.ets、RecorderService.ets、LocationStamper.ets、AlbumSaver.ets、Prefs.ets、DeviceFacts.ets、ServiceLocator.ets
      design/                  Tokens.ets（T → ResourceColor / vp / fp）、L10n.ets（tr）、Components.ets（StatusDot、GlassBar、Pill、PrimaryButton）
      pages/                   Root.ets（Navigation 栈）、Login.ets、ProjectPicker.ets、Home.ets、Library.ets、Viewer.ets、Queue.ets、Settings.ets
  README.md                  构建、签名、模拟器、走查清单、已知限制
```

`tests/harmony/`（仓库根）：`contract-fixtures.test.ts`（五夹具）、`recording-clock.test.ts`、`upload-naming.test.ts`、`iso-time.test.ts`、`library-grouping.test.ts`。

## 3. 领域层（纯 ArkTS，Node 可跑）

语义与安卓 §3 完全一致，这里只记 ArkTS 写法：

- `enum TransferState { waiting = 'waiting', … }`；`TransferStateOps.fromRaw / next / recovered / applyingStatus / phaseOf / caption / detail / whereItIs` 放在一个 `class` 的静态方法里（ArkTS 不允许给 enum 挂方法）。
- 迁移表来自 `ContractStates.transitions: Transition[]`（生成物里的显式 `interface Transition { from: string; event: string; to: string | null; guard?: string }`）。
- `TransferTally.of(items)`、`LibraryGrouping.byProject / byDay / deleteWarningLevel / deleteWarning`、`UploadNaming.fileName(item)`（`现场影像-yyyyMMdd-HHmmss-xxxx.jpg|mp4` / `现场录音-….m4a`，前缀走词典键 `file.prefix.*`）、`IsoTime.format/parse`（写 `yyyy-MM-dd'T'HH:mm:ssXXX`，读宽容）。
- `RecordingClock`：`elapsedBase`、`resumedAt`、`paused`；`start(at)`、`interrupt(at)`、`resume(at)`、`elapsed(at)`——与 iOS `RecordingClock` 同名同语义，界面计时与通知文案都从它派生。
- **ArkTS 硬约束（子代理必读）**：对象字面量必须有显式类/接口类型；无 `any/unknown`；无对象解构与对象展开（数组展开可以）；无 `typeof`/`keyof` 类型查询；无 `in` 运算符；无索引签名与计算属性名；无 `Symbol`；类字段必须初始化或标 `!`；`Record<string, T>` 字面量可用；`Map` 优先于用对象当字典；泛型箭头函数不行用函数声明。生成器与手写代码都按这套写，`hvigorw` 构建带 ArkTS 检查，编不过就是没遵守。

## 4. 服务层

| 服务 | 鸿蒙实现 | 与安卓的差异 |
|---|---|---|
| Backend | `@ohos.net.http` `createHttp()`，JSON 请求；`X-Session-Id` 头；信封 `code==4010` → 清会话抛 `Unauthorized`，`code!=0` → `ApiError`；裸响应直解 | 上传不走这里（见 Uploader） |
| SessionStore | Asset Store Kit `asset.add/query/remove`，alias `sessionId` | 密钥库替代 EncryptedSharedPreferences |
| EvidenceStore | `context.filesDir/FieldEvidence/{media,manifest}`；`save()`：`fs.moveFile` 原件 → `hash.hash(path,'sha256')` → 写 `manifest/{id}.json`（先 `.tmp` 再 `rename`）；`loadAll/updateState/setProject/markSavedToAlbum/delete/sweepOrphans`；一把 Promise 链锁串行 | 无协程，用 `async` + 链锁 |
| UploadQueue | 单飞标志 + 链锁；`kick()` 开头把滞留 `uploading` 件 `recovered()`；退避 60s×2^n≤15min；`retryFailed/autoKick/checkDelivered`（`mediaStatus` 每批 50） | 语义照抄安卓 `UploadQueue.kt` |
| Uploader | `request.agent.create(context, { action: UPLOAD, url: base+'/api/mobile/media', method: 'POST', mode: BACKGROUND, headers: {'X-Session-Id'}, data: [deviceId, projectKey, clientMediaId, fileName, mediaType, capturedAt, file{path, filename, mimeType}], gauge: true, retry: false, overwrite: true })`；`on('progress')` 回进度；`on('completed')` 成功、`on('failed')` 失败（`TaskInfo.faults` 转成 `lastError`）；HTTP 4xx/5xx 算失败；完成后 `request.agent.remove(tid)` | 替代 OkHttp 多部分请求；系统托管后台续传 |
| CameraService | Camera Kit：`XComponent(type SURFACE)` 出 surfaceId → `PreviewOutput`；`PhotoOutput.capture()` + `on('photoAvailable')` 取主图 buffer 写 `.jpg`；录像 `VideoOutput` + `AVRecorder(videoSourceType SURFACE_YUV, fileFormat CFT_MPEG_4, fd)` 出 `.mp4`；后置镜头、竖屏 | 照片不二次编码不改 EXIF；录像不限时；切后台停录像落库 |
| RecorderService | 见 §5 | 进程级单例；停录自己落库 |
| LocationStamper | `geoLocationManager.getCurrentLocation({ priority: FIRST_FIX, timeoutMs: 8000 })` 一次 | 精度取 `accuracy` |
| AlbumSaver | `Prefs.saveToAlbum` 为真时 `photoAccessHelper.showAssetsCreationDialog(srcUris, [{title, fileNameExtension, photoType}])`，用户确认后 `fs.copyFile` 到返回的目标 uri；只加不读；音频不存 | 默认关（H8） |
| Prefs | `preferences.getPreferences(context, 'prefs')`：`saveToAlbum: boolean`、`selectedProject: string(JSON)` | — |
| DeviceFacts | `deviceInfo.marketName`、`deviceInfo.osFullName`、`bundleManager.getBundleInfoForSelf` 出版本 | — |

## 5. 录音后台续录（#407）

- `module.json5`：`backgroundModes: ["audioRecording"]`（在 EntryAbility 上），权限 `ohos.permission.KEEP_BACKGROUND_RUNNING`、`ohos.permission.MICROPHONE`。
- `RecorderService`（进程级单例）：`start(project, loc)` → 建 `wantAgent`（回 EntryAbility）→ `backgroundTaskManager.startBackgroundRunning(context, AUDIO_RECORDING, wantAgent)` → `AVRecorder.prepare(config)` → `start()`；`RecordingClock.start(now)`；`state`（`@ObservedV2` 类：`isRecording / startedAt / interrupted / clock`）供 Home 观察。
- 中断（三重兜底，因 AVRecorder 无 audioInterrupt 事件）：`on('stateChange')` 收到 `paused` → `clock.interrupt`、`interrupted = true`；收到 `started` → `clock.resume`、`interrupted = false`；`on('error')` 码 `AVERR_AUDIO_INTERRUPTED` 同按中断记；回前台 `AppModel.onForeground` 调 `RecorderService.resumeIfInterrupted()` 补一次 `recorder.resume()`（通话结束用户直接切回应用那条路上不一定有事件）。`stopped` / `error` 状态按停止处理（落库）。来电中断只能真机验证。
- 停止：`stop()` → `recorder.stop(); release()` → `stopBackgroundRunning` → `EvidenceStore.save(audio, file, startedAt, loc, project)` → `queue.kick()`；不存相册。位置取**开录时**快照（与安卓一致）。
- Home 切后台（`onBackground`）只停录像与相机，**不停录音**；录音舞台显示 `home.audio.backgroundOk`，中断时显示 `rec.paused.interrupted`。
- 常驻展示：长时任务的系统通知（点击回应用）。实况窗：留卡，待 AGC 批 TIMER 场景权限后做 `liveViewManager.startLiveView({ id, event: 'TIMER', timer: { time: startedAt, isCountdown: false, isPaused }, liveViewData: { primary: { title: tr('home.recording.audio'), content: [...] } } })`，中断时 `updateLiveView` 置 `isPaused`。

## 6. 权限与 module.json5

`requestPermissions`：`ohos.permission.INTERNET`、`ohos.permission.CAMERA`、`ohos.permission.MICROPHONE`、
`ohos.permission.APPROXIMATELY_LOCATION`、`ohos.permission.LOCATION`、`ohos.permission.KEEP_BACKGROUND_RUNNING`。
用户授权类（相机、麦克风、定位）在首次进入取景器时 `abilityAccessCtrl.requestPermissionsFromUser` 一次问齐；
`reason` 文案走 `$string:` 资源（用途说明措辞对齐 iOS purpose string 与 `android/store/permissions.md`）。
不申请存储读写、不申请通知发布（长时任务通知由系统发）。

`abilities[0]`：`EntryAbility`，`backgroundModes: ["audioRecording"]`，`orientation: portrait`，`exported: true`，`skills` home。

## 7. 界面（ArkUI，令牌全部来自 `T`）

`Root.ets` 用 `Navigation` + `NavPathStack`，与安卓根路由一致。屏与要点照安卓 §5；鸿蒙差异：

| 屏 | 差异 |
|---|---|
| Login | `TextInput` 手机/邮箱 + 6 位验证码自动提交；`Tabs` 或两枚 Pill 切短信/邮箱，默认短信 |
| ProjectPicker | `List` + `LoadingProgress`；空态、错误重试、退出登录 |
| Home（深） | `Stack`：`XComponent` 预览铺满 → 左下水印（`Text` 叠加，只叠不烧）→ 顶栏（项目名 / 归档路径 / 三桶计数 / GPS / 设置）→ 底栏三档 `Pill` + 大快门 + 最近缩略图 + 桌面端在线态；录音中显示计时与 `home.audio.backgroundOk`；权限缺失显示 `home.permission.*` 与「去设置」（`common.open` 跳系统设置） |
| Library（深） | `Grid`/`List` 切换、按项目分组按日分段、多选删除三级警告（`AlertDialog`）；顶栏 `GlassBar` 用 `.backdropBlur(T.blur)`（契约 `glassBlur: true` 兑现） |
| Viewer（深） | `Swiper` 横滑同日条目；图片 `Image` + `PinchGesture`；视频/音频 `Video` 组件（音频也用 Video 只出控制条） |
| Queue（浅） | 四段 `List` 分组；行：缩略图、`StatusDot`、进度、失败原因、SHA 前 12 位、重试；末行 `library.otherPending`；页面可见时每 20 秒 `checkDelivered` |
| Settings（浅） | 存相册 `Toggle`（默认关，副标题说明每件会弹系统确认）、归档目标、账号（服务器 / 退出 / 注销）、用量、关于 |

深浅色：Home / Library / Viewer 深，其余浅（与安卓一致）；令牌 `T.L / T.D`。全部用户可见文案走 `tr(key, vars)`，
缺键回显键名；不在 `.ets` 里写取证主流程中文字面量（`check.mjs` 扫 `harmony/entry/src/main/**/*.ets`）。

## 8. 契约侧改动（走 contract-change）

1. `contract/tools/lib.mjs` ArkTS 渲染器重写：`Tokens.ets` 出 `interface` + `export const T: Tokens = {...}`（无 `as const`）；`Strings.ets` 保持 `Record<string, Record<string, string>>`；`States.ets` 出 `interface Transition` 与 `interface ContractStatesShape` + 类型化常量；`Capabilities.ets` 出接口 + 常量。新增 `harmony/contract/Index.ets` 汇出四个文件（也是生成物）。
2. `check.mjs` 内联扫描加 `harmony/entry/src/main`（`.ets`），并加一条：`harmony/build-profile.json5` 出现 `storePassword` 即红（H11）。
3. `scripts/node-ts-resolve.mjs` 扩 `.ets` 转译与 `contract` 别名（H2）；`package.json` 的 `test` glob 已覆盖 `tests/**`。
4. `capabilities.json` 鸿蒙列按实测校正：`backgroundUpload: true`（request.agent 后台）、`glassBlur: true`（backdropBlur）、`backgroundRecording: true`、`deviceAttestation: false`、`continuousSegments: false`、`maxVideoSeconds: null`——预计不改值。
5. 新文案键（先进 `strings.json` 再用）：`settings.saveToAlbum.dialogHint`（「开启后每件影像保存时会弹系统确认」）、`home.permission.location`（「需要定位权限才能记录拍摄地点」）。其余复用现有键。

## 9. 构建、签名、模拟器（README 内容）

- 构建（不开 IDE）：`export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk && export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node && cd harmony && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon`。产物 `entry/build/default/outputs/default/entry-default-unsigned.hap`（未配签名时）。
- 依赖：`/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install --all`（首次）。
- 调试签名（用户动作，一次）：DevEco 打开 `harmony/` → 登录华为开发者账号 → File › Project Structure › Signing Configs › Automatically generate signature。生成的材料在 `~/.ohos/config/`，写进 `build-profile.json5` 的 `signingConfigs` 块**不提交**。
- 模拟器（用户动作，一次）：DevEco Device Manager 下载 phone 镜像（HarmonyOS 7.0.0(26.0.0)，Pura 90 Pro 实例已建）并接受许可；之后 CLI `Emulator -start "Pura 90 Pro"`、`hdc list targets`、`hdc install <hap>`、`hdc shell aa start -a EntryAbility -b com.aiworkdeck.mobile.huawei`、截图 `hdc shell snapshot_display -f /data/local/tmp/x.jpeg && hdc file recv …`。
- 发布：`.p12` + AGC 发布证书 + 发布 Profile（待建）配到 `signingConfigs.release`，`hvigorw assembleApp -p buildMode=release` 出 `.app` 交 AGC。出包脚本另卡。

## 10. 测试与验收

1. **第一件事**（根 CLAUDE.md 规则 6）：`tests/harmony/contract-fixtures.test.ts` 读 `contract/fixtures/*.json` 驱动 ArkTS 领域函数（tally / transitions / restore / status-merge / delete-warning），`npm test` 绿。
2. Node 单测：`RecordingClock`、文件名与日期格式、分组分段、退避序列（`UploadQueue` 的纯逻辑部分抽 `Backoff`）。
3. `node contract/tools/check.mjs` 绿（含 harmony 扫描）；`hvigorw assembleHap` 绿（ArkTS 检查零错误）。
4. 模拟器走查（需 §9 两个用户动作完成后）：登录 → 选项目 → 拍照 / 录像 / 录音各一 → 队列见上传中 → 已暂存 → 图集按日分组、删除三级警告 → 设置注销入口可达；**录音开录 → Home 键 → 30 秒后回来计时连续、停止后落库入队**；每屏截图。
5. CI：`contract.yml` 已跑 `check.mjs + npm test`，天然覆盖 harmony 领域层；hvigor 构建 CI 不做（runner 无 DevEco），README 写明「构建靠本机」。
