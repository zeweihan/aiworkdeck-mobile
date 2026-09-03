# 录音后台续录与常驻展示（四端）设计

dev-board：[#404 iOS](https://github.com/zeweihan/dev-board/issues/404)、
[#405 安卓](https://github.com/zeweihan/dev-board/issues/405)、
[#406 小程序](https://github.com/zeweihan/dev-board/issues/406)、
[#407 鸿蒙](https://github.com/zeweihan/dev-board/issues/407)。

## 起因

用户开会用 Voice Memos 录音，常「录一半就停」。本仓 iOS 与安卓首页**在退后台时主动停录**
（`HomeView.onChange(scenePhase)`、`HomeScreen` 的 `ON_STOP` 观察者），正是同类行为；
两端都没处理来电/系统中断。小程序 onHide 不停录音，但没接微信通话打断的恢复。

## 目标

1. 录音中切后台、锁屏，录音继续。
2. 被系统中断（来电、Siri、闹钟、微信通话）后，中断结束**自动续录进同一段**。
3. 有常驻展示：iOS 灵动岛 + 锁屏 Live Activity（计时、停止按钮）；安卓常驻通知
   （计时、停止），Android 16 提升为 Live Updates；鸿蒙实况窗。
4. **只改录音**。录像是用户深入动作，不容易被误暂停，维持退后台即停并落库。

## 契约

`capabilities.json` 新增：

```
"backgroundRecording": { "ios": true, "miniprogram": false, "android": true, "harmony": true,
                         "degradedNotice": "cap.noBackgroundRecording" }
```

小程序标 `false`：微信文档只承诺 `requiredBackgroundModes: audio` 用于后台播放，后台录音
未见官方结论；真机（iOS/安卓微信）核验后若续录成立再翻为 `true`。

`strings.json` 新增键（zh-Hans / en）：

| 键 | zh-Hans | 用处 |
|---|---|---|
| `cap.noBackgroundRecording` | 小程序切到后台或锁屏后录音可能中断，请保持微信在前台 | 小程序录音页提示 |
| `home.audio.backgroundOk` | 切到后台、锁屏也会继续录音 | iOS/安卓录音中提示 |
| `rec.paused.interrupted` | 通话中，录音已暂停，结束后自动继续 | 三端中断态 |
| `notify.channel.recording` | 录音 | 安卓通知渠道名 |

复用已有键：`home.recording.audio`（录音中）、`home.shutter.stopAudio`（停止录音）。

## iOS（#404）

**Info.plist**：`UIBackgroundModes: [audio]`、`NSSupportsLiveActivities: true`。

**RecordingClock（纯逻辑，可单测）**：`elapsedBase`（本次运行前累计秒）、`resumedAt`、
`paused`。操作：`start(at)`、`interrupt(at)`、`resume(at)`、`elapsed(at)`。
计时器与 Live Activity 的内容状态都从它派生，两处显示不会各算各的。

**AudioRecorderService**：改为进程级单例 `AudioRecorderService.shared`（停止意图要从
主进程找到它）。监听 `AVAudioSession.interruptionNotification`：`.began` → 时钟
`interrupt`、`isInterrupted = true`（AVAudioRecorder 已被系统暂停）；`.ended` → 不论
`shouldResume` 一律尝试 `recorder.record()` 续写同一文件，成功则 `resume`。会话类别仍
`.record`。`recordingSeconds` 由时钟计算。

**Live Activity**：
- 共享类型 `RecordingActivityAttributes`（`projectName`）+ `ContentState`
  （`elapsedBase`、`resumedAt`、`paused`），同时编进 App 与扩展。
- 扩展 target `WorkdeckLiveActivity` / `WorkdeckCNLiveActivity`（XcodeGen `app-extension`，
  WidgetKit 扩展点），源码 `ios/LiveActivity/`。灵动岛紧凑态：红点 + 计时；展开态：
  项目名、计时、「停止录音」按钮；锁屏卡同展开态。计时用
  `Text(timerInterval:)` 自走，不靠推送刷新；暂停时显示静态 `elapsedBase`。
- 停止按钮走 `StopRecordingIntent: LiveActivityIntent`，在**主进程**执行，通过
  `StopRecordingIntent.handler` 静态钩子调 `AudioRecorderService.shared.stop()`；扩展里
  钩子为空，从不在扩展内执行。
- `RecordingActivityController`（App target）负责 `Activity.request` / `update` / `end`，
  由 service 在开录、中断、续录、停止时调用。
- Bundle id：`com.aiworkdeck.mobile.LiveActivity` / `com.aiworkdeck.mobile.cn.LiveActivity`。
  Debug 与 App 同样不签名；Release 手动签名。国际版 `sigh` 多签一份；**大陆版描述文件
  由用户按 ASC API 路子再建一份**，CI 多一个 `CN_LA_PROFILE_B64` secret。

**HomeView**：`recorder` 改用 `.shared`；`.background` 分支只停录像与相机，不停录音；
录音舞台在录音中显示 `home.audio.backgroundOk`，中断时显示 `rec.paused.interrupted`。

**测试**：`RecordingClockTests`（开始/中断/续录/多次中断的累计秒）；模拟器 iPhone 15 Pro
以上验证灵动岛出现、切后台 60 秒回来计时连续、锁屏停止按钮落库。

## 安卓（#405）

**Manifest**：`FOREGROUND_SERVICE_MICROPHONE`；
`<service android:name=".services.RecordingService" android:foregroundServiceType="microphone" android:exported="false"/>`。
Android 14 起 microphone 服务必须在前台启动；开录本来就是前台点按钮，无冲突。

**RecordingService（前台服务）**：持有 MediaRecorder（沿用 `AudioRecorderService` 的
编码参数），`startForeground(type MICROPHONE)`。通知渠道 `recording`
（`IMPORTANCE_DEFAULT`，无声音），`setOngoing`、`setUsesChronometer` + `setWhen(startedAt)`、
动作「停止录音」（PendingIntent → `ACTION_STOP`）、点通知回 `MainActivity`；
`setRequestPromotedOngoing(true)` 让 Android 16 提升为 Live Updates。
开录参数（项目、位置快照）经 `RecordingState.request` 传入，不走 Intent extras。
停止时服务自己落库：`ServiceLocator.store.save` → `UploadWorker.enqueue` → `queue.kick`，
然后向 `RecordingState.stored` 发事件，`AppModel` 收到后 `refresh()`。
位置取**开录时**快照（此前取按停时；取证语义上开录地点更对，且服务拿不到界面里的定位）。

**RecordingState（进程级单例，Compose 可观察）**：`isRecording`、`startedAt`、
`interrupted`（预留，安卓 MediaRecorder 通话期间不主动暂停）。`HomeScreen` 观察它，
不再 `remember { AudioRecorderService }`；`ON_STOP` 与 `onDispose` 只停录像。

**商店材料**：`android/store/permissions.md` 补 `FOREGROUND_SERVICE_MICROPHONE`；
`checklist-google-play.md` 补前台服务类型申报（Play 要求说明与演示视频）。

**测试**：`RecordingStateTest`（请求/开录/停止/事件）；模拟器验证 Home 键 60 秒后回来
计时连续、通知停止按钮落库进队列。

## 小程序（#406）

`utils/recorder.ts`：`onInterruptionBegin` → 记 `interrupted`，回调 UI 显示
`rec.paused.interrupted`；`onInterruptionEnd` → `manager.resume()`；页面 `onShow` 时若
`interrupted` 仍为真再补一次 `resume()`。录音页在 `CAPS.backgroundRecording === false`
时显示 `DEGRADED_NOTICE` 对应文案。真机核验切后台/锁屏是否续录，结论记回 #406。

## 鸿蒙（#407，随首版实现）

`AVRecorder` 录音；开录时 `backgroundTaskManager.startBackgroundRunning(context,
BackgroundMode.AUDIO_RECORDING, wantAgent)`，`module.json5` 声明
`backgroundModes: ["audioRecording"]` 与 `ohos.permission.KEEP_BACKGROUND_RUNNING`；
音频焦点中断（`INTERRUPT_HINT_PAUSE/RESUME`）后自动续录；实况窗走 Live View Kit，
需先在 AGC 申请实况窗权限。契约 `backgroundRecording.harmony = true`。

## 不做

- 录像后台续录（iOS 不允许后台用摄像头；产品上录像也不需要）。
- 安卓通话期间的主动暂停/续录（MediaRecorder 自行处理，不同厂商行为不一，不额外建模）。
- 小米「超级岛」等厂商私有 API（需白名单）。
- Live Activity 推送更新（计时本地自走，不需要）。
