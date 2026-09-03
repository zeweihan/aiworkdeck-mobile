# 鸿蒙客户端首版 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `harmony/` 建起 HarmonyOS NEXT（ArkTS）客户端，对位安卓全功能七屏，录音从第一版起支持后台续录。

**Architecture:** 单工程 `harmony/`：`contract` HAR（契约生成物）+ `entry` HAP。`entry/src/main/ets/` 按 `model / services / design / pages` 分层；领域层是不引 `@ohos/@kit` 的纯 ArkTS，用仓库根 `npm test`（Node）跑契约夹具；服务层用 file.fs / request.agent / AVRecorder / backgroundTaskManager / Camera Kit；界面 ArkUI `Navigation` 栈。

**Tech Stack:** DevEco Studio 26.0.0、HarmonyOS SDK API 26、hvigor 6.26.4、ArkTS/ArkUI（stage 模型）、`@ohos.net.http`、`@ohos.request` agent、`@ohos.multimedia.media` AVRecorder、`@ohos.multimedia.camera`、`@ohos.resourceschedule.backgroundTaskManager`、`@kit.AssetStoreKit`、`@ohos.data.preferences`、`@ohos.file.fs` / `@ohos.file.hash`。

**Spec:** `docs/specs/2026-09-03-harmony-client-design.md`（沿用 `docs/specs/2026-09-02-android-client-design.md`，录音见 `docs/specs/2026-09-03-background-recording-design.md`）。安卓源码 `android/app/src/main/kotlin/com/aiworkdeck/mobile/` 是最贴近的行为参考，每个任务先读对应的 Kotlin 文件再写 ArkTS。

## Global Constraints

- 包名 `com.aiworkdeck.mobile.huawei`；服务端 `https://addin.aiworkdeck.com`；只有一个 product `default`。
- `compatibleSdkVersion` 目标 `5.0.0(12)`，`targetSdkVersion` = 本机 SDK（API 26）；字符串写法以 hvigor 接受为准（Task 1 定）。
- 状态名、桶名、文案、令牌、能力开关**只来自 `contract/`**；改契约先改 JSON 再 `node contract/tools/gen.mjs`；生成物不手改。
- 用户可见文案一律 `tr(key, vars)`；不在 `.ets` 里写取证主流程中文字面量（`check.mjs` 扫 `harmony/entry/src/main`）。新增文案先进 `contract/strings.json`。
- ArkTS 硬约束（spec §3）：对象字面量必须有显式类/接口类型；无 `any/unknown`；无对象解构与对象展开；无 `typeof/keyof` 类型查询；无 `in`；无索引签名与计算属性名；无 `Symbol`；类字段必须初始化或标 `!`；字典用 `Map` 或 `Record<string, T>`；泛型箭头函数改函数声明。
- 领域层 `.ets` 文件不得 import 任何 `@ohos.*` / `@kit.*`（Node 要能跑）。
- 签名不进仓：`harmony/build-profile.json5` 的 `signingConfigs` 保持 `[]`；出现 `storePassword` 即契约校验红。
- 构建命令（每个任务收尾必跑，零 ArkTS 错误才算过）：
  ```bash
  export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
  export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node
  cd harmony && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
  ```
- 仓库根三件套（每个任务收尾必跑）：`node contract/tools/check.mjs && npm test && npm run typecheck`。
- 子代理**不提交**；主会话审查后提交。每个任务的汇报格式：改了哪些文件、跑了哪些命令、**命令输出原文**（构建尾部 + 测试摘要）、未验证项如实标注。
- 模拟器与调试签名是用户动作（spec §9），未就绪时界面任务只做编译验证，并在汇报里标「模拟器未验证」。

---

### Task 1: 契约 ArkTS 渲染器 + Node 夹具通道 + 工程脚手架（编译打通）

**Files:**
- Modify: `contract/tools/lib.mjs`（`renderEtsTokens / renderEtsStrings / renderEtsStates / renderEtsCaps`，`outputs()` 增 `harmony/contract/Index.ets`）
- Modify: `contract/tools/check.mjs`（`checkInline` 加 `harmony/entry/src/main` 的 `.ets`；新增 `checkHarmonySigning`）
- Modify: `scripts/node-ts-resolve.mjs`（`.ets` 转译 + `contract` 别名）
- Modify: `contract/strings.json`（新增 `settings.saveToAlbum.dialogHint`、`home.permission.location`），跑 gen 刷新四端生成物
- Create: `harmony/build-profile.json5`、`harmony/hvigorfile.ts`、`harmony/hvigor/hvigor-config.json5`、`harmony/oh-package.json5`、`harmony/code-linter.json5`、`harmony/.gitignore`、`harmony/AppScope/app.json5`、`harmony/AppScope/resources/base/element/string.json`、`harmony/AppScope/resources/base/media/`（图标先用 iOS `ios/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png` 缩成 `app_icon.png` 与 `layered_image.json` 所需前景/背景）
- Create: `harmony/contract/oh-package.json5`、`harmony/contract/build-profile.json5`、`harmony/contract/hvigorfile.ts`、`harmony/contract/src/main/module.json5`（HAR）、`harmony/contract/Index.ets`（生成物）
- Create: `harmony/entry/oh-package.json5`、`harmony/entry/build-profile.json5`、`harmony/entry/hvigorfile.ts`、`harmony/entry/src/main/module.json5`、`harmony/entry/src/main/resources/base/{element/string.json,element/color.json,media/,profile/main_pages.json}`、`harmony/entry/src/main/ets/entryability/EntryAbility.ets`、`harmony/entry/src/main/ets/pages/Root.ets`（临时：一行 `Text(tr('home.eyebrow'))`，证明 HAP 引到了 HAR）
- Create: `harmony/entry/src/main/ets/design/L10n.ets`
- Create: `tests/harmony/l10n.test.ts`
- Create: `harmony/README.md`（骨架：构建、签名、模拟器命令，照 spec §9）

**Interfaces（生成物形状，后续任务全靠它）:**
```ts
// harmony/contract/src/main/ets/Tokens.ets
export interface TokensL { bg: string; sunken: string; fg: string; fgMuted: string; fgFaint: string; rule: string; ruleStrong: string; accent: string; accentWash: string }
export interface TokensD { bg: string; surface: string; fg: string; fgMuted: string; rule: string }
export interface TokensS { waiting: string; moving: string; arrived: string; failed: string; waitingOnDark: string; movingOnDark: string; arrivedOnDark: string }
export interface TokensSp { s1: number; s2: number; s3: number; s4: number; s5: number; s6: number; s8: number; s10: number; s16: number; gutter: number }
export interface TokensTy { hero: number; display: number; title: number; heading: number; body: number; small: number; micro: number; nano: number }
export interface TokensMotion { fastMs: number; baseMs: number; slowMs: number }
export interface Tokens { L: TokensL; D: TokensD; S: TokensS; Sp: TokensSp; Ty: TokensTy; Motion: TokensMotion; touchMin: number; contractVersion: number }
export const T: Tokens = { ... }          // 接口字段由 JSON 键与值类型推出（string / number），渲染器通用，不手写字段名
// Strings.ets
export const ContractStrings: Record<string, Record<string, string>> = { ... }   // 不变
// States.ets
export interface Transition { from: string; event: string; to: string; guard?: string }
export interface ContractStatesShape { version: number; states: string[]; aliases: Record<string, string>; phaseOf: Record<string, string>; phaseLabelKey: Record<string, string>; phaseDot: Record<string, string>; failedDot: string; stateTextKey: Record<string, string>; stateDetailKey: Record<string, string>; whereKey: Record<string, string>; retryDelaysMs: number[]; maxAutoRetries: number; events: string[]; transitions: Transition[]; deleteWarnOrder: string[]; deleteWarnLevel: Record<string, string>; deleteWarnKey: Record<string, string> }
export const ContractStates: ContractStatesShape = { ... }
// Capabilities.ets
export interface ContractCapabilitiesShape { client: string; backgroundUpload: boolean; maxVideoSeconds: number | null; continuousSegments: boolean; glassBlur: boolean; deviceAttestation: boolean; backgroundRecording: boolean; degradedNotice: Record<string, string> }
export const ContractCapabilities: ContractCapabilitiesShape = { ... }   // 字段类型由 harmony 列的值推：boolean→boolean，number→number，null→number | null，string→string
// harmony/contract/Index.ets（生成物）
export * from './src/main/ets/Tokens'   // 若 ArkTS 不接受 export *，改为逐个具名导出（接口也要导）
export * from './src/main/ets/Strings'
export * from './src/main/ets/States'
export * from './src/main/ets/Capabilities'
// harmony/entry/src/main/ets/design/L10n.ets
export function tr(key: string, vars?: Record<string, string | number>): string   // 固定 zh-Hans；缺键回显键名；{k} 逐个替换
```
- Produces: 可编译的 `harmony/` 工程；`import { T, ContractStates, ContractStrings, ContractCapabilities, Transition } from 'contract'` 在 entry 里可用；Node 里 `import { tr } from '../../harmony/entry/src/main/ets/design/L10n.ets'` 可跑。

- [ ] **Step 1: 改渲染器（`contract/tools/lib.mjs` §ArkTS）**

  通用工具：`etsIface(name, obj)` 按对象一层键出 `interface`（值 `typeof === 'number'` → `number`，否则 `string`）；`renderEtsTokens` 出六个子接口 + `Tokens` + `export const T: Tokens = JSON`；`renderEtsStates` 出 `Transition`、`ContractStatesShape` + 类型化常量；`renderEtsCaps` 出 `ContractCapabilitiesShape` + 常量；去掉所有 `as const`。`outputs()` 加 `['harmony/contract/Index.ets', renderEtsIndex()]`。文件头仍用 `H('//')`。

- [ ] **Step 2: 加文案键、跑生成**

  `contract/strings.json` 追加：
  ```json
  "settings.saveToAlbum.dialogHint": { "zh-Hans": "开启后每件影像保存时会弹出系统确认", "en": "Each capture will ask for confirmation before saving" },
  "home.permission.location": { "zh-Hans": "需要定位权限才能记录拍摄地点", "en": "Location permission is needed to stamp where this was taken" }
  ```
  运行 `node contract/tools/gen.mjs`，确认 `harmony/contract/src/main/ets/*.ets`、`harmony/contract/Index.ets` 与四端其他生成物都刷新；`git diff --stat` 只该有生成物与 strings.json。

- [ ] **Step 3: `check.mjs`**

  `checkInline` 的 `files` 加 `...walk(join(c.root, 'harmony', 'entry', 'src', 'main'), ['.ets'], [])`。新增：
  ```js
  function checkHarmonySigning(c, problems) {
    const p = join(c.root, 'harmony', 'build-profile.json5')
    if (existsSync(p) && /storePassword|keyPassword/.test(readFileSync(p, 'utf8')))
      problems.push('harmony/build-profile.json5 含签名口令：signingConfigs 不进仓，改回 []')
  }
  ```
  在 `runChecks` 里 `checkGenerated` 之后调用。

- [ ] **Step 4: Node 通道 `scripts/node-ts-resolve.mjs`**

  ```js
  import { register } from 'node:module'
  import { readFileSync } from 'node:fs'
  import { pathToFileURL } from 'node:url'
  import { join } from 'node:path'
  import ts from 'typescript'
  register(import.meta.url, import.meta.url)
  const ROOT = new URL('..', import.meta.url)
  export async function resolve(specifier, context, nextResolve) {
    if (specifier === 'contract') return { url: new URL('harmony/contract/Index.ets', ROOT).href, shortCircuit: true }
    try { return await nextResolve(specifier, context) }
    catch (err) {
      if (err && err.code === 'ERR_MODULE_NOT_FOUND' && specifier.startsWith('.')) {
        try { return await nextResolve(`${specifier}.ts`, context) }
        catch { return nextResolve(`${specifier}.ets`, context) }
      }
      throw err
    }
  }
  export async function load(url, context, nextLoad) {
    if (!url.endsWith('.ets')) return nextLoad(url, context)
    const src = readFileSync(new URL(url), 'utf8')
    const out = ts.transpileModule(src, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } })
    return { format: 'module', source: out.outputText, shortCircuit: true }
  }
  ```
  注意 `.ets` 内部相对 import 不带扩展名，走同一套重试；`register` 的钩子文件既是入口又是钩子（现有写法保留）。

- [ ] **Step 5: 写 `L10n.ets` 与它的失败测试**

  `tests/harmony/l10n.test.ts`：
  ```ts
  import { test } from 'node:test'
  import assert from 'node:assert/strict'
  import { tr } from '../../harmony/entry/src/main/ets/design/L10n.ets'
  test('tr: 占位替换与缺键回显', () => {
    assert.equal(tr('delete.title', { n: 3 }), '删除 3 件')
    assert.equal(tr('tally.failedSuffix', { m: 2 }), '含 2 失败')
    assert.equal(tr('no.such.key'), 'no.such.key')
  })
  ```
  `npm test` 先红（模块不存在），再写：
  ```ts
  import { ContractStrings } from 'contract'
  export function tr(key: string, vars?: Record<string, string | number>): string {
    const entry = ContractStrings[key]
    let s: string = entry !== undefined ? entry['zh-Hans'] : key
    if (vars !== undefined) {
      const keys = Object.keys(vars)
      for (let i = 0; i < keys.length; i++) s = s.split('{' + keys[i] + '}').join(String(vars[keys[i]]))
    }
    return s
  }
  ```
  `npm test` 绿。

- [ ] **Step 6: 脚手架**

  按 DevEco 模板（`/Applications/DevEco-Studio.app/Contents/plugins/openharmony/lib/templates/{project/New Project,ability/Empty Ability,module/New Module}/code template/`）手写各文件；`hvigor-config.json5` 的 `modelVersion` 取本机 hvigor 接受的值（先试 `"6.26.4"`，报错按提示改）；`build-profile.json5` products：`{ name: 'default', signingConfig: 'default', targetSdkVersion, compatibleSdkVersion: '5.0.0(12)', runtimeOS: 'HarmonyOS', buildOption: { strictMode: { caseSensitiveCheck: true, useNormalizedOHMUrl: true } } }`，`modules: [ { name: 'entry', srcPath: './entry', targets: [{ name: 'default', applyToProducts: ['default'] }] }, { name: 'contract', srcPath: './contract', targets: [...] } ]`。`entry/oh-package.json5` `dependencies: { "contract": "file:../contract" }`。`AppScope/app.json5`：`bundleName com.aiworkdeck.mobile.huawei`，`versionCode 1`，`versionName "1.0.0"`，`label $string:app_name`（值「AI WorkDeck」）。`module.json5`：`EntryAbility`，`srcEntry ./ets/entryability/EntryAbility.ets`，`backgroundModes: ["audioRecording"]`，`orientation: "portrait"`，`exported: true`，home skill；`requestPermissions` 六项（spec §6，带 `reason: "$string:perm_xxx"` 与 `usedScene`）。`Root.ets` 临时页。
  运行 `ohpm install --all`（`/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm`），再跑 Global Constraints 里的构建命令。**版本字符串、modelVersion、useNormalizedOHMUrl、HAR 的 `export *` 等一切与 hvigor 较劲的地方以构建通过为准，把最终值写进 README。**

- [ ] **Step 7: 收尾验证**

  `node contract/tools/check.mjs && npm test && npm run typecheck` 全绿；`hvigorw assembleHap` 绿并列出产物路径；`git status` 确认 `oh_modules/`、`.hvigor/`、`build/`、`local.properties` 未入库。汇报构建输出尾部 20 行与 `npm test` 摘要原文。

---

### Task 2: 领域层 + 契约夹具适配测试 + 设计令牌层

**Files:**
- Create: `harmony/entry/src/main/ets/model/Capture.ets`、`model/TransferState.ets`、`model/TransferTally.ets`、`model/LibraryGrouping.ets`、`model/UploadNaming.ets`、`model/IsoTime.ets`、`model/RecordingClock.ets`、`model/Backoff.ets`、`model/AppModelLogic.ets`、`model/Envelope.ets`
- Create: `harmony/entry/src/main/ets/design/Tokens.ets`、`design/Components.ets`
- Create: `tests/harmony/contract-fixtures.test.ts`、`tests/harmony/recording-clock.test.ts`、`tests/harmony/upload-naming.test.ts`、`tests/harmony/iso-time.test.ts`、`tests/harmony/library-grouping.test.ts`、`tests/harmony/backoff.test.ts`、`tests/harmony/envelope.test.ts`

**Interfaces:**
```ts
// model/Capture.ets
export enum MediaKind { photo = 'photo', video = 'video', audio = 'audio' }
export class MediaKindOps { static ext(k: MediaKind): string /* jpg|mp4|m4a */; static mediaType(k: MediaKind): string /* image|video|audio */ }
export interface CaptureManifest { clientMediaId: string; sha256: string; capturedAt: string; serverReceivedAt?: string; latitude?: number; longitude?: number; horizontalAccuracy?: number; deviceModel: string; osVersion: string; appVersion: string; fromCamera: boolean; tsaToken?: string }
export interface RelayProject { deviceId: string; deviceName?: string; key: string; name: string }
export function projectId(p: RelayProject): string          // `${deviceId}:${key}`
export interface StoredRow { kind: string; state: string; progress: number; manifest: CaptureManifest; lastError?: string; savedToAlbum?: boolean; project?: RelayProject }
export class CaptureItem { id: string; kind: MediaKind; state: TransferState; manifest: CaptureManifest; localPath: string; progress: number; lastError: string | null; savedToAlbum: boolean; project: RelayProject | null; capturedAtMs(): number }
// model/TransferState.ets
export enum TransferState { waiting='waiting', uploading='uploading', uploaded='uploaded', arrived='arrived', failed='failed' }
export enum TransferEvent { kick='kick', http2xx='http_2xx', httpError='http_error', networkError='network_error', retryManual='retry_manual', retryAuto='retry_auto', statusDelivered='status_delivered', statusPending='status_pending', appLaunch='app_launch' }
export enum TransferPhase { uploading='uploading', staged='staged', landed='landed' }
export interface StatusMerge { state: TransferState; waitingSeconds: number | null; expiresAt: string | null }
export class TransferStateOps {
  static fromRaw(s: string): TransferState | null            // 经 ContractStates.aliases
  static next(s: TransferState, e: TransferEvent, attempts: number): TransferState | null   // 无规则 null；guard 不满足原态
  static recovered(s: TransferState, attempts: number): TransferState
  static applyingStatus(s: TransferState, delivered: boolean, waitingSeconds: number, expiresAt: string | null): StatusMerge
  static phaseOf(s: TransferState): TransferPhase
  static caption(s: TransferState): string; static detail(s: TransferState): string; static whereItIs(s: TransferState): string
  static phaseCaption(p: TransferPhase): string; static dotToken(s: TransferState): string   // 'S.waiting' 等
}
// model/TransferTally.ets
export interface Tally { uploading: number; failed: number; staged: number; landed: number; total: number }
export function tallyOf(states: TransferState[]): Tally
// model/LibraryGrouping.ets
export interface DaySection { key: string; title: string; items: CaptureItem[] }
export interface DeleteWarn { level: string; n: number }
export function groupByDay(items: CaptureItem[]): DaySection[]         // 本地自然日，新的在前；标题 tr('library.dayTitle', {m,d,n})
export function deleteWarningLevel(states: TransferState[]): DeleteWarn
export function deleteWarning(states: TransferState[]): string
// model/UploadNaming.ets
export function uploadFileName(kind: MediaKind, capturedAtMs: number, clientMediaId: string): string  // `${tr('file.prefix.media'|'file.prefix.audio')}-yyyyMMdd-HHmmss-${id前4位}.${ext}`
// model/IsoTime.ets
export function formatIso(ms: number): string        // yyyy-MM-dd'T'HH:mm:ss+08:00（本地偏移）
export function parseIso(s: string): number | null   // 宽容：带偏移/Z/小数秒；无偏移按本地
// model/RecordingClock.ets
export class RecordingClock { elapsedBase: number = 0; resumedAt: number | null = null; paused: boolean = true;
  start(at: number): void; interrupt(at: number): void; resume(at: number): void; elapsed(at: number): number /* 秒 */ }
// model/Backoff.ets
export class Backoff { seconds: number = 60; nextAt: number = 0; onFailure(now: number): void /* nextAt=now+seconds*1000; seconds=min(seconds*2,900) */; reset(): void /* seconds=60 */ }
// model/AppModelLogic.ets
export const DESKTOP_ONLINE_WINDOW_MS: number = 180000
export function otherPendingCount(items: CaptureItem[], selected: RelayProject | null): number
export function isDesktopOnline(lastSeenMs: number | null, nowMs: number): boolean
// model/Envelope.ets（纯解析，Backend 用）
export class ApiError extends Error { code: number }
export class Unauthorized extends Error {}
export function checkEnvelope(obj: Record<string, Object>): void   // code 4010 抛 Unauthorized；code!=0 抛 ApiError(message)；无 code 不抛
// design/Tokens.ets
export class Tk { static readonly L = T.L; static readonly D = T.D; static readonly S = T.S; static readonly Sp = T.Sp; static readonly Ty = T.Ty; static readonly touchMin = T.touchMin; static color(token: string): string /* 'S.waiting' → T.S.waiting */ }
// design/Components.ets：@Component StatusDot({ color: string, size?: number })、Pill({ label, selected, onTap })、GlassBar（.backdropBlur(20) + 半透明底）、PrimaryButton
```
- Consumes: Task 1 的 `contract` 导出与 `tr`。
- Produces: 上面全部签名；后续任务只从这里取领域函数。

- [ ] **Step 1: 先写夹具测试（红）** `tests/harmony/contract-fixtures.test.ts`：
  ```ts
  import { test } from 'node:test'
  import assert from 'node:assert/strict'
  import { readFileSync } from 'node:fs'
  import { join } from 'node:path'
  import { TransferStateOps, TransferState, TransferEvent } from '../../harmony/entry/src/main/ets/model/TransferState.ets'
  import { tallyOf } from '../../harmony/entry/src/main/ets/model/TransferTally.ets'
  import { deleteWarningLevel } from '../../harmony/entry/src/main/ets/model/LibraryGrouping.ets'
  const fx = (n: string) => JSON.parse(readFileSync(join(import.meta.dirname, '..', '..', 'contract', 'fixtures', `${n}.json`), 'utf8'))
  const st = (s: string): TransferState => { const v = TransferStateOps.fromRaw(s); if (v === null) throw new Error(s); return v }
  const ev = (s: string): TransferEvent => Object.values(TransferEvent).find((e) => e === s) as TransferEvent
  test('fixture: tally', () => { for (const k of fx('tally').cases) assert.deepEqual(tallyOf(k.states.map(st)), k.expect, k.name) })
  test('fixture: transitions', () => { for (const k of fx('transitions').cases) assert.equal(TransferStateOps.next(st(k.from), ev(k.event), k.attempts), k.to === null ? null : st(k.to), `${k.from}+${k.event}(${k.attempts})`) })
  test('fixture: restore', () => { for (const k of fx('restore').cases) assert.equal(TransferStateOps.recovered(st(k.state), k.attempts), st(k.expect)) })
  test('fixture: status-merge', () => { for (const k of fx('status-merge').cases) assert.deepEqual(TransferStateOps.applyingStatus(st(k.state), k.status.delivered, k.status.waitingSeconds, k.status.expiresAt ?? null), { state: st(k.expect.state), waitingSeconds: k.expect.waitingSeconds, expiresAt: k.expect.expiresAt }, k.name) })
  test('fixture: delete-warning', () => { for (const k of fx('delete-warning').cases) assert.deepEqual(deleteWarningLevel(k.states.map(st)), k.expect, JSON.stringify(k.states)) })
  test('alias: moving → uploading', () => assert.equal(TransferStateOps.fromRaw('moving'), TransferState.uploading))
  ```
  其余测试文件（时钟：start→interrupt→resume 多次累计秒；文件名 `现场影像-20260903-101500-abcd.jpg` 与录音前缀；ISO 往返与 `2026-09-09T10:00:00`（无偏移）解析；分组：跨日两段、段内倒序、标题含「M月d日 · N 件」；退避 60→120→…→900 封顶、成功复位；信封 4010/非零/无 code）各自先红后绿。

- [ ] **Step 2: 实现领域层**（语义逐条对照 `android/.../model/*.kt`、`AppModelLogic.kt`、`services/UploadNaming.kt`、`ios/Sources/Services/RecordingClock.swift`）。`groupByDay` 用 `Date` 的本地 getter；`formatIso` 手拼偏移。全部符合 ArkTS 约束。
- [ ] **Step 3: `design/Tokens.ets`、`design/Components.ets`**（组件用到令牌与 `tr`，暂不接页面）。
- [ ] **Step 4: 验证** `npm test` 全绿（列出用例数）；`hvigorw assembleHap` 绿（领域文件即使未被页面引用也会参与 ArkTS 检查——若不参与，在 `Root.ets` 里临时 import 一下）；`check.mjs` 绿。

---

### Task 3: 服务层（会话、偏好、设备事实、Backend、EvidenceStore、Uploader、UploadQueue、ServiceLocator）

**Files:**
- Create: `harmony/entry/src/main/ets/services/SessionStore.ets`、`Prefs.ets`、`DeviceFacts.ets`、`Backend.ets`、`ApiTypes.ets`、`EvidenceStore.ets`、`Uploader.ets`、`UploadQueue.ets`、`ServiceLocator.ets`

**Interfaces:**
```ts
// ApiTypes.ets
export interface AccountUser { id: number; username: string; displayName: string; avatarUrl?: string; role?: string }
export interface LoginResult { sessionId: string; isNewUser?: boolean; mustBindPhone?: boolean; user: AccountUser }
export interface MediaStatus { clientMediaId: string; delivered: boolean; waitingSeconds: number; expiresAt?: string }
export interface MediaUsage { usedBytes: number; quotaBytes: number }
export interface UploadResult { code: number; id: number; clientMediaId: string; delivered: boolean }
// SessionStore.ets（Asset Store Kit，alias 'sessionId'）
export class SessionStore { async current(): Promise<string | null>; async save(id: string): Promise<void>; async clear(): Promise<void> }
// Prefs.ets（@ohos.data.preferences 'prefs'）
export class Prefs { constructor(ctx: common.Context); async saveToAlbum(): Promise<boolean> /* 默认 false */; async setSaveToAlbum(v: boolean): Promise<void>; async selectedProject(): Promise<RelayProject | null>; async setSelectedProject(p: RelayProject | null): Promise<void> }
// DeviceFacts.ets
export interface DeviceFacts { model: string; osVersion: string; appVersion: string }
export function deviceFacts(ctx: common.Context): DeviceFacts
// Backend.ets（@ohos.net.http；BASE_URL = 'https://addin.aiworkdeck.com'）
export class Backend { constructor(baseUrl: string, session: SessionStore)
  async sendLoginCode(phone: string): Promise<void>; async verifyLoginCode(phone: string, code: string): Promise<LoginResult>
  async sendMailLoginCode(email: string): Promise<void>; async verifyMailLoginCode(email: string, code: string): Promise<LoginResult>
  async deleteAccount(): Promise<void>; async logout(): Promise<void>; async hasSession(): Promise<boolean>
  async myProjects(): Promise<RelayProject[]>; async mediaUsage(): Promise<MediaUsage>; async mediaStatus(ids: string[]): Promise<MediaStatus[]> }
// EvidenceStore.ets（root = ctx.filesDir + '/FieldEvidence'）
export interface Loc { lat: number; lon: number; accuracy: number | null }
export class EvidenceStore { constructor(root: string, facts: DeviceFacts)
  async save(kind: MediaKind, tempPath: string, capturedAtMs: number, loc: Loc | null, project: RelayProject | null): Promise<CaptureItem>
  async loadAll(): Promise<CaptureItem[]>   // 按 capturedAt 降序
  async updateState(id: string, to: TransferState, progress: number, error: string | null): Promise<void>
  async setProject(id: string, p: RelayProject): Promise<void>; async markSavedToAlbum(id: string): Promise<void>
  async remove(ids: string[]): Promise<void>; async sweepOrphans(): Promise<number> }
// Uploader.ets（request.agent，BACKGROUND）
export class Uploader { constructor(ctx: common.Context, baseUrl: string, session: SessionStore)
  async upload(item: CaptureItem, project: RelayProject, fileName: string, onProgress: (p: number) => void): Promise<UploadResult> }  // HTTP 非 2xx / 任务 failed → 抛 ApiError；4010 → Unauthorized
// UploadQueue.ets
export enum KickResult { done='done', hasMoreWaiting='hasMoreWaiting', alreadyRunning='alreadyRunning' }
export class UploadQueue { constructor(store: EvidenceStore, uploader: Uploader, backend: Backend)
  progress: Map<string, number>; onChange: (() => void) | null = null; nextAutoKickAt: number
  consumeUnauthorized(): boolean
  async kick(): Promise<KickResult>; async autoKick(): Promise<void>; async retryFailed(): Promise<void>
  async checkDelivered(): Promise<Map<string, string>> /* id(lower) → expiresAt */ }
// ServiceLocator.ets（进程级单例，EntryAbility.onCreate 里 init(ctx)）
export class ServiceLocator { static init(ctx: common.Context): void; static ctx: common.Context; static session: SessionStore; static prefs: Prefs; static backend: Backend; static store: EvidenceStore; static queue: UploadQueue }
```
- Consumes: Task 2 全部领域类型、`Backoff`、`checkEnvelope`、`uploadFileName`、`formatIso`。
- Produces: 上述服务，供 AppModel/页面调用。

- [ ] **Step 1: 逐个对照安卓实现**（`services/{SessionStore,Prefs,DeviceFacts,Backend,EvidenceStore,Uploader,UploadQueue,ServiceLocator}.kt`），语义一致：save 三步序（原件 → `hash.hash(path,'sha256')` → manifest 先 `.tmp` 再 `fs.rename`）、串行锁（`private chain: Promise<void>`，每个公开方法 `this.chain = this.chain.then(work)`）、`kick()` 单飞 + `recoverStale`、退避用 `Backoff`、`checkDelivered` 每批 50、`lastUnauthorized` 标记。
- [ ] **Step 2: Uploader**：`request.agent.create(ctx, config)`，`config = { action: request.agent.Action.UPLOAD, url, method: 'POST', mode: request.agent.Mode.BACKGROUND, headers: { 'X-Session-Id': sid }, data: [ {name:'deviceId', value}, {name:'projectKey', value}, {name:'clientMediaId', value}, {name:'fileName', value}, {name:'mediaType', value}, {name:'capturedAt', value}, {name:'file', value: { path: item.localPath, filename: fileName, mimeType }} ], gauge: true, retry: false, overwrite: true, saveas: undefined }`；`task.on('progress', p => onProgress(p.processed / max(1, p.sizes[0])))`；`on('completed')` 解析响应（`TaskInfo.extras` 或 `on('response')` 的 `statusCode`；先查 `@ohos.request.d.ts` 里 `TaskInfo.extras` 与 `HttpResponse` 的注释再决定，把结论写进代码注释）；`on('failed')` → `ApiError(taskInfo.faults)`；两种终态都 `request.agent.remove(tid)`。`path` 若不接受沙箱绝对路径，改成把文件拷到 `cacheDir` 后用 `internal://cache/...`，并在成功后删缓存副本。
- [ ] **Step 3: 验证** `hvigorw assembleHap` 绿；`npm test`、`check.mjs` 绿。汇报里注明 Uploader 响应体的取法与依据（d.ts 行号）。

---

### Task 4: AppModel + 根路由 + 登录 / 选项目 / 设置三屏

**Files:**
- Create: `harmony/entry/src/main/ets/AppModel.ets`、`pages/Root.ets`（重写）、`pages/Login.ets`、`pages/ProjectPicker.ets`、`pages/Settings.ets`
- Modify: `entryability/EntryAbility.ets`（`ServiceLocator.init`、`onForeground` → `AppModel.shared.onForeground()`）

**Interfaces:**
```ts
@ObservedV2 export class AppModel { static shared: AppModel
  @Trace route: 'boot' | 'login' | 'projects' | 'home' = 'boot'
  @Trace items: CaptureItem[]; @Trace selectedProject: RelayProject | null; @Trace desktopLastSeenMs: number | null; @Trace usage: MediaUsage | null
  async bootstrap(): Promise<void>   // sweepOrphans → hasSession? → selectedProject? → route；启动 60s 心跳（autoKick + consumeUnauthorized → signOut）
  async refresh(): Promise<void>; async signOut(): Promise<void>; async selectProject(p: RelayProject): Promise<void>
  async store(kind: MediaKind, tempPath: string, capturedAtMs: number, loc: Loc | null): Promise<CaptureItem>   // save → 存相册? → queue.kick
  tally(): Tally /* 只数当前项目 */; desktopOnline(): boolean; onForeground(): void }
```
Navigation：`Root.ets` 持 `NavPathStack`；`route` 变化时 `replacePath`；Library/Queue/Viewer 用 `pushPath`。
- Login：短信默认 / 邮箱切换；两步验证码；6 位自动提交；错误用 `promptAction.showToast`；文案键 `login.*`。
- ProjectPicker：`myProjects()`；空态 `empty.projects` / `project.emptyTitle`；`project.retry`；退出登录 `common.signOut`。
- Settings：`settings.*`：存相册 `Toggle`（默认关，副标题 `settings.saveToAlbum.dialogHint`）；归档目标 → 回 ProjectPicker；账号（服务器 / 退出 / 注销 → `AlertDialog` `settings.deleteAccount.confirm`）；用量 `mediaUsage` 进度条；关于（版本、包名）。

- [ ] Step 1: AppModel（对照 `AppModel.kt`）；Step 2: 三屏（浅色令牌 `Tk.L`）；Step 3: 构建 + 三件套；模拟器可用时走：登录（审核账号见项目记忆 `mobile-local-verify-recipe`，不入仓）→ 选项目 → 设置各项 → 注销回登录，截图三张。

---

### Task 5: 录音服务（AVRecorder + 长时任务 + 中断续录）

**Files:**
- Create: `harmony/entry/src/main/ets/services/RecorderService.ets`、`services/RecordingState.ets`
- Modify: `AppModel.ets`（收到 `RecorderService.onStored` 后 `refresh()`）

**Interfaces:**
```ts
@ObservedV2 export class RecordingState { @Trace isRecording: boolean = false; @Trace startedAt: number = 0; @Trace interrupted: boolean = false; clock: RecordingClock = new RecordingClock(); @Trace elapsedSec: number = 0 /* 1s 定时刷新 */ }
export class RecorderService { static shared: RecorderService; state: RecordingState
  async start(project: RelayProject | null, loc: Loc | null): Promise<boolean>   // startBackgroundRunning(AUDIO_RECORDING, wantAgent→EntryAbility) → AVRecorder prepare/start → clock.start
  async stop(): Promise<CaptureItem | null>                                       // recorder.stop/release → stopBackgroundRunning → store.save(audio, path, startedAt, loc, project) → queue.kick → onStored
  onStored: ((item: CaptureItem) => void) | null }
```
AVRecorder 配置：`{ audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC, profile: { audioBitrate: 64000, audioChannels: 1, audioCodec: media.CodecMimeType.AUDIO_AAC, audioSampleRate: 44100, fileFormat: media.ContainerFormatType.CFT_MPEG_4A }, url: 'fd://' + fd }`，文件在 `cacheDir/rec-<uuid>.m4a`。中断：`recorder.on('audioInterrupt', e)`：`e.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE` → `clock.interrupt(now)`、`interrupted=true`；`INTERRUPT_HINT_RESUME` → `await recorder.resume()` 成功后 `clock.resume(now)`、`interrupted=false`；`INTERRUPT_HINT_STOP` → `stop()`。`stateChange` 里若系统把状态置 `paused` 而未收到 hint，同样按中断记。

- [ ] Step 1: 实现；Step 2: 构建绿；Step 3（模拟器可用时）：开录 → Home 键 → 30 秒 → 回来 `elapsedSec` 连续、系统通知栏见长时任务通知 → 停止 → 队列有该件；`hdc shell hilog | grep RecorderService` 贴日志。

---

### Task 6: 取景首页（相机 / 录像 / 录音三档、水印、定位、存相册）

**Files:**
- Create: `services/CameraService.ets`、`services/LocationStamper.ets`、`services/AlbumSaver.ets`、`pages/Home.ets`、`pages/HomeWatermark.ets`（纯格式化：时间 / 项目 / 坐标±精度）
- Test: `tests/harmony/watermark.test.ts`（对照 `android/.../home/WatermarkFormat.kt` 与 `WatermarkFormatTest.kt`）

**Interfaces:**
```ts
export class CameraService { async open(surfaceId: string): Promise<void>; async close(): Promise<void>; async takePhoto(): Promise<string> /* 临时 jpg 路径 */; async startVideo(): Promise<void>; async stopVideo(): Promise<string> /* 临时 mp4 */; isRecordingVideo: boolean }
export class LocationStamper { async current(): Promise<Loc | null> /* 8s 超时，失败 null */ }
export class AlbumSaver { async saveIfEnabled(item: CaptureItem): Promise<void> /* Prefs.saveToAlbum 为真且 kind≠audio 时 showAssetsCreationDialog → 拷贝 → markSavedToAlbum */ }
export function watermarkLines(nowMs: number, projectName: string | null, loc: Loc | null): string[]
```
Home（深色 `Tk.D`）：`Stack`：`XComponent({ type: XComponentType.SURFACE })` 预览 → 左下水印（`Text` 叠加）→ 顶栏：`home.eyebrow`、项目名、`home.archiveTo` + `archive.path`（`现场影像 / yyyy-MM-dd`）、三桶计数（`tally.*`）、GPS 精度（`home.gps.accuracy` / `home.gps.none`）、设置入口 → 底栏：三档 `Pill`（`home.mode.*`）、大快门（`home.shutter.*`）、最近缩略图（进 Library）、桌面端在线态（`home.desktop.online/offline`）。权限：首次 `requestPermissionsFromUser([CAMERA, MICROPHONE, APPROXIMATELY_LOCATION, LOCATION])`；缺相机/麦克风显示 `home.permission.camera/mic` + `common.open`（`abilityAccessCtrl` 打开设置）。拍照：`takePhoto` → `AppModel.store(photo, path, now, loc)`；录像：切后台（`EntryAbility.onBackground` 广播）停录像落库；录音：`RecorderService.shared.start/stop`，录音中显示计时与 `home.audio.backgroundOk`，`interrupted` 时 `rec.paused.interrupted`。位置在开拍/开录**时**取快照。

- [ ] Step 1: watermark 测试红→绿；Step 2: 服务与页面；Step 3: 构建绿；模拟器可用时拍照/录像/录音各一，队列各一件，截图。

---

### Task 7: 图集 + 查看器

**Files:** `pages/Library.ets`、`pages/Viewer.ets`；Modify `Root.ets`（push 路由）

Library（深）：项目菜单（当前项目第一）、按日分段 `Grid`（列数 2/3 切换 `library.columns`）与 `List` 视图（`library.viewGrid/viewList`，选择持久化到 Prefs 增 `libraryView` 键）、多选（`library.select/selectedCount/delete`）→ `AlertDialog`（标题 `delete.title`，正文 `deleteWarning(states)`）→ `store.remove` → `refresh`；空态 `library.empty`；顶栏 `GlassBar`。Viewer（深）：`Swiper` 同日条目、图片 `Image` + `PinchGesture` 缩放、视频/音频 `Video` 组件；底部状态点 + `TransferStateOps.detail` + sha 前 12 位 + 时间。

- [ ] 实现 → 构建绿 → 模拟器走查（分组、删除三级警告、查看器滑动）截图。

---

### Task 8: 上传队列页 + 轮询

**Files:** `pages/Queue.ets`；Modify `AppModel.ets`（页面可见时 20 秒 `checkDelivered` 定时器）

Queue（浅）：四段 `queue.section.failed/uploading/staged/landed`（有件才显示）；行：缩略图、`StatusDot`、进度条（`queue.progress`）、失败原因、sha 前 12 位、`queue.expires`（到期）、失败段头 `queue.retryAll` → `queue.retryFailed()`；末行 `library.otherPending`（`otherPendingCount`）。

- [ ] 实现 → 构建绿 → 模拟器走查（上传中 → 已暂存 → 桌面端取件后已落盘）截图。

---

### Task 9: README、契约能力校正、走查与截图归档

- `harmony/README.md` 完整版（spec §9 + 走查清单 + 已知限制：存相册弹窗、实况窗待 AGC、hvigor CI 不做、英文未开）。
- 按实测校正 `contract/capabilities.json` 的 harmony 列（预计不变），跑 gen。
- 七屏截图 + 录音 30 秒后台续录截图放 `.superpowers/sdd/2026-09-03-harmony-client/`（不入库，附 PR）。
- 主会话：提交、PR、CI、合并；#391 / #407 落实记录；实况窗另开卡。
