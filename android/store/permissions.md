# 安卓权限清单与用途说明

来源：`android/app/src/main/AndroidManifest.xml`（权限声明）与
`android/app/src/main/kotlin/com/aiworkdeck/mobile/features/home/HomeScreen.kt`
（实际请求时机与拒绝后的行为，2026-09 读码确认，不是猜测）。措辞对齐 iOS
`ios/project.yml` 里的 purpose string（`NSCameraUsageDescription` 等），中文商店与英文
Play 商店各写一份人话版本。

## 权限表

| 权限 | 类型 | 何时请求 | 用途（对齐 iOS 措辞） | 可选 | 拒绝后的行为 |
|---|---|---|---|---|---|
| `android.permission.CAMERA` | 运行时敏感权限 | 首次进入拍摄主界面（取景器）时，与麦克风、定位、通知一起一次性弹窗（见下方「一次问齐」） | 拍摄现场资料与取证影像。影像只保存在本应用内，不写入系统相册。 | 否，核心功能 | 照片/录像模式显示「缺少相机权限」的引导页（可点击跳转系统设置），无法拍摄；录音模式不受影响，仍可用 |
| `android.permission.RECORD_AUDIO` | 运行时敏感权限 | 同上，一次性弹窗 | 现场录音取证与录像收声都需要使用麦克风，录到的声音只作为取证记录保存。 | 部分可选：录音模式必需；录像模式可降级 | 录音模式显示「缺少麦克风权限」引导页，无法录音；录像模式仍可拍摄，但视频不带音轨（CameraService 判断未授权时跳过 `withAudioEnabled()`）；拍照不受影响 |
| `android.permission.ACCESS_FINE_LOCATION` | 运行时敏感权限 | 同上，一次性弹窗 | 记录每张影像的拍摄地点，写入归档信息。仅在拍摄时读取一次，不做后台定位。 | 是，非阻塞 | 拍摄不受影响，仅归档信息里没有 GPS 坐标与精度（取景器顶部的定位圆点保持未点亮状态） |
| `android.permission.ACCESS_COARSE_LOCATION` | 运行时敏感权限 | 与 `ACCESS_FINE_LOCATION` 同一批请求（Android 权限组机制：声明 FINE 时系统同时列出 COARSE 供用户选择「精确/大致」） | 同上；用户在系统弹窗里选「仅在使用时允许精确位置」还是「大致位置」都在覆盖范围内 | 是，非阻塞 | 同上；若只拿到 COARSE，归档坐标精度会更粗——这一分支未见专门处理代码，标记待核 |
| `android.permission.POST_NOTIFICATIONS` | 运行时权限（仅 Android 13 / API 33+） | 同上，一次性弹窗（API<33 无需请求，通知默认可发） | 上传中的前台任务需要举一条「正在上传现场影像」的进度通知。 | 是，非阻塞 | 上传队列照常在后台跑完，只是看不到系统通知栏里的进度提示（`android/README.md` 已记录的已知限制，Android 12+ 后台启动前台服务通知本身还会被系统进一步限制） |
| `android.permission.FOREGROUND_SERVICE` | install-time / 普通权限，无用户弹窗 | 安装时系统自动授予 | 支撑上传队列在应用退到后台后继续跑（`androidx.work` 前台任务） | 不适用 | 不适用（用户无法拒绝） |
| `android.permission.FOREGROUND_SERVICE_DATA_SYNC` | install-time / 普通权限，无用户弹窗 | 安装时系统自动授予 | 声明前台服务类型为「数据同步」，即退到后台后继续把已拍摄的取证影像上传到中转服务器 | 不适用 | 不适用；Play 「权限声明」表单需要为此类型单独写一段用途说明，见下方 |
| `android.permission.INTERNET` | install-time / 普通权限，无用户弹窗 | 安装时系统自动授予 | 上传影像、登录、拉取项目列表等所有网络请求 | 不适用 | 不适用 |

**没有存储/相册写入权限**：iOS 有 `NSPhotoLibraryAddUsageDescription`（用户主动导出时写入系统相册），
Android 侧的「同时存入系统相册」开关（设置页）在 API 29+ 用 `MediaStore` 以应用私有身份写入，
不需要声明 `WRITE_EXTERNAL_STORAGE` 之类的危险权限，因此清单里没有对应项，这不是遗漏。

**一次问齐**：相机、麦克风、定位（Android 13+ 再加通知）四项在首次进入拍摄主界面时用一个
`RequestMultiplePermissions` 合并成一次系统弹窗，不分三次问——现场按快门前连点三个对话框体验差
（见 `HomeScreen.kt` 里的注释）。这意味着商店审核如果模拟「首次启动」，应期待看到一次弹窗而不是逐权限单独弹。

## 国内商店「权限用途说明」（可直接粘贴）

```
相机：用于拍摄现场取证照片与视频，影像仅保存在应用内，不写入系统相册。
麦克风：用于现场录音取证，以及录制视频时同步收音，录到的声音仅作为取证记录保存。
定位（精确位置）：用于在拍摄时记录该张影像的拍摄地点（GPS 坐标与精度），写入归档信息；
仅在拍摄时读取一次，不进行后台持续定位。
通知：用于在影像上传过程中展示进度通知（仅 Android 13 及以上系统需要）。
存储/网络：应用需要联网将现场影像上传至中转服务器，桌面端确认落盘后中转副本即被删除。
```

## Google Play「Permissions declaration」填写要点

- `FOREGROUND_SERVICE_DATA_SYNC`：用途说明填「Uploading user-captured evidence (photos, video,
  audio) to the developer's relay server after the app has been backgrounded, so an in-progress
  transfer is not interrupted when the user switches away from the app. The relay copy is deleted
  as soon as the desktop app confirms the file has been written to disk.」
- `CAMERA` / `RECORD_AUDIO` / `ACCESS_FINE_LOCATION`：这三项是 Play 标准运行时权限，通常不需要在
  Permissions declaration 表单里单独申报用途（该表单主要针对后台位置、通话记录、短信等敏感权限组），
  但 Data safety 表单（见 `data-safety.md`）里仍要如实申报「位置」类数据的采集与用途。
- `POST_NOTIFICATIONS`：标准运行时权限，无需单独申报。
