# 四端共享契约（contract/）设计

2026-09-02。dev-board：#389（安卓分发）、#391（鸿蒙立项）派生。

维护者拍板安卓走 Kotlin + Compose 原生、鸿蒙走 ArkTS 原生之后，本产品是四个原生端：
iOS（Swift）、微信小程序（WXML/TS）、安卓（Kotlin）、鸿蒙（ArkTS）。README 里
「一致性不靠共享 UI 代码，靠共享契约」这句话在两端时靳得住手抄，四端时每处漂移乘四。
维护者要求：**契约要写得科学**，且**规矩必须跨会话被触发，不能只活在一次对话里**。

## 0. 现状（2026-09-02，main @ e11caf0）

契约今天是散文加两份手抄，且已在漂：

| 项 | 现状 |
|---|---|
| 状态机 | 同一「上传中」状态 iOS 叫 `moving`，小程序叫 `uploading`；都是落盘的持久化字符串 |
| 三桶映射 | `TransferPhase`（Swift）与 `phase.ts`（TS）各写一份，改一次人肉对两次 |
| 文案 | 两端各自内联；首页计数标签曾把已抵达标成「已上传」 |
| 令牌 | `tokens.wxss` 是源，`Tokens.swift` 手抄；两处注释都说有 `scripts/check-tokens.mjs` 对拍，**该脚本不存在** |
| API | 服务端 `MobileRelayController` 返回 `Map<String,Object>`，无类型化 DTO，无 OpenAPI；接口形状只在 relay spec 的表格里 |
| 能力差 | README 一张散文表 + 小程序 `capability.ts`；iOS 无对应物 |
| 测试 | 小程序 `tests/phase.test.ts`（node --test）、iOS `WorkdeckTests`（阶段映射、分组、删除文案） |
| CI | 移动仓只有 `cla.yml`；服务端仓有 `ci.yml` |

## 1. 决策记录

维护者 2026-09-02 拍板，不再重开：

| # | 决策 | 理由 |
|---|---|---|
| C1 | 契约只管语义与数据，不管布局 | 四平台像素级规范不现实也没人维护；「逐像素一致」层用参考截图 + 尺寸标注文档约束 |
| C2 | API 真源在服务端仓，手写 OpenAPI 3.0.3；移动仓钉版本消费 | 服务端返回 `Map`，springdoc 推不出字段；手写 YAML + 服务端契约测试，DTO 渐进补 |
| C3 | 纯数据生成，行为校验 | 令牌 / 文案 / 状态枚举 / 能力常量是纯数据，四个小生成器；迁移逻辑各端手写，跑同一套夹具 |
| C4 | 内部状态正式名以小程序那组为准：`waiting / uploading / uploaded / arrived / failed` | 多数派；iOS 只需 `moving → uploading` 一处改名 + 解码别名，不迁移数据 |
| C5 | 文案词典从第一天带 `en` 栏 | Google Play 国际版迟早要；键值结构下加一栏零成本 |
| C6 | 规矩以「不依赖任何人记得」的方式落地 | 见 §8：项目级 CLAUDE.md、项目级 skill、编辑钩子、pre-commit、CI、服务端契约测试五层 |

## 2. 目录

移动仓：

```
contract/
  contract.json            版本号 + 文件清单 + 各文件 sha256（校验器的锚）
  transfer-state.json      五态、三桶、映射、迁移、点色、删除警告等级
  strings.json             文案词典：key → { zh-Hans, en }
  tokens.json              设计令牌单一来源（取代 tokens.wxss 的源地位）
  capabilities.json        四端能力声明 + 降级提示文案键
  api/
    mobile-v1.yaml         服务端 OpenAPI 的钉版副本
    PINNED.json            服务端仓 commit sha + 副本 sha256 + 拉取时间
  fixtures/
    tally.json             条目列表 → 三桶计数（含「含 N 失败」）
    transitions.json       事件序列 → 终态
    status-merge.json      status 轮询响应 → 状态与 waitingSeconds/expiresAt 回填
    restore.json           冷启动回拨
    delete-warning.json    所选状态 → 警告等级
  tools/
    gen.mjs                生成器
    check.mjs              校验器
    pull-api.mjs           从本机 checkba_cloud（CHECKBA_CLOUD_DIR 可覆盖）拉 OpenAPI 并更新 PINNED.json
    hook-post-edit.mjs     Claude Code PostToolUse 钩子入口
    wxss-footer.css        tokens.wxss 尾部三个工具类（非令牌）
  README.md                改契约的操作步骤（与 skill 同源）
```

服务端仓 checkba_cloud：

```
backend/src/main/resources/openapi/mobile-v1.yaml     API 真源
backend/src/test/java/.../MobileApiContractTest.java  MockMvc 打每个端点，响应对 YAML 校验
```

## 3. 状态机 `transfer-state.json`

### 3.1 五态（内部，落盘）

| 正式名 | 含义 | 落盘字符串 | 别名（只解码不编码） |
|---|---|---|---|
| `waiting` | 在手机上，未开始传 | `waiting` | |
| `uploading` | 正在传到中转区 | `uploading` | iOS 旧值 `moving` |
| `uploaded` | 已进中转区，等桌面端取回 | `uploaded` | |
| `arrived` | 桌面端已 ACK 落盘，中转区已删 | `arrived` | |
| `failed` | 上次上传失败，可重试 | `failed` | |

### 3.2 三桶（展示）

| 桶 | 含义 | 成员 | 桶名文案键 | 点色令牌 |
|---|---|---|---|---|
| `uploading` | 还在手机上 | waiting, uploading, failed | `phase.uploading` | `S.waiting`（failed 用 `S.failed`） |
| `staged` | 在中转区 | uploaded | `phase.staged` | `S.moving` |
| `landed` | 在电脑上 | arrived | `phase.landed` | `S.arrived` |

计数：`{ uploading, failed, staged, landed }`，`failed ⊆ uploading`。展示
「N 上传中（含 M 失败）」，M 为 0 不显示括号。**计数只数当前项目**。

令牌名 `S.waiting / S.moving / S.arrived` 不改（PR #15 决定），契约里用 `dot` 字段显式记桶到令牌的映射。

### 3.3 迁移

| 起 | 事件 | 终 | 备注 |
|---|---|---|---|
| waiting | `kick` | uploading | 逐件用条目自带的 project |
| uploading | `http_2xx` | uploaded | 幂等键 clientMediaId，重复上传返回既有记录也算 2xx |
| uploading | `http_error` / `network_error` | failed | 记 `lastError`、`attempts += 1` |
| failed | `retry_manual` | waiting | |
| failed | `retry_auto` | waiting | 仅 `attempts <= maxAutoRetries`；`retryDelaysMs = [5000, 15000, 45000]` 是契约常量，`maxAutoRetries` 定义为其长度（3） |
| uploaded | `status.delivered == true` | arrived | 中转区已删 |
| uploaded | `status.delivered == false` | uploaded | 回填 `waitingSeconds`、`expiresAt` |
| uploading | `app_launch` | waiting | 冷启动回拨：被杀时卡在传输中的条目重排队 |
| failed | `app_launch` | waiting | 仅 `attempts <= maxAutoRetries`，与小程序 `recoverOnLaunch` 现行为一致 |
| 任意 | `delete_local` | （移除） | 任何状态允许删，警告等级见 3.4 |

不允许的迁移一律视为契约违约，夹具里有反例。

### 3.4 删除警告等级

按所选条目里最坏的桶说话：含 `uploading` 桶 → 等级 `unsent`；否则含 `staged` → 等级 `staged`；
否则 `landed`。三个等级各对应一个文案键（`delete.warn.unsent` 等），文案带 `{n}` 占位。

## 4. 文案词典 `strings.json`

```json
{
  "phase.uploading": { "zh-Hans": "上传中", "en": "Uploading" },
  "state.uploaded.detail": { "zh-Hans": "已暂存 · 等待桌面端接收", "en": "" }
}
```

键命名 `域.对象[.修饰]`。初版域：`phase`（桶名）、`state`（单件文案）、`where`（在哪）、
`tally`（计数标签，含 `{n}` `{m}` 占位）、`delete`（删除警告）、`cap`（能力降级提示）、
`empty`（空态）。`en` 可空字符串，校验器只在 `--strict-en` 下要求非空。

规则：取证主流程（相机、队列、图集、归档确认）界面文案**不许内联**，校验器对四端源码
grep 词典里已有的中文值，命中即红。平台化层（设置、导航）不在此限。

## 5. 设计令牌 `tokens.json`

现有 `tokens.wxss` 与 `Tokens.swift` 的值原样搬入，结构按 `L`（浅色）/ `D`（深色）/
`S`（状态色，含 onDark 变体）/ `Sp`（间距）/ `Ty`（字号）分组，与 Swift 现有枚举名一致。

单位规则写进契约：**基准 pt**。wxss 侧间距乘 2 出 rpx；字号统一 px 不换算（rpx 随屏宽缩放，
小屏正文会掉到 14px 以下，这是既有决定）；Kotlin 出 dp/sp；ArkTS 出 vp/fp。
颜色统一 `#RRGGBB` 或 `rgba()`，生成器负责转平台写法。

## 6. 能力矩阵 `capabilities.json`

```json
{
  "backgroundUpload":     { "ios": true,  "miniprogram": false, "android": true, "harmony": true,
                            "degradedNotice": "cap.noBackgroundUpload" },
  "maxVideoSeconds":      { "ios": null,  "miniprogram": 60,    "android": null, "harmony": null },
  "continuousSegments":   { "ios": false, "miniprogram": true,  "android": false, "harmony": false,
                            "degradedNotice": "cap.segmentedRecording" },
  "glassBlur":            { "ios": true,  "miniprogram": "runtime", "android": "runtime", "harmony": true },
  "deviceAttestation":    { "ios": true,  "miniprogram": false, "android": false, "harmony": false }
}
```

`"runtime"` 表示运行时探测（小程序 `capability.ts` 那套逻辑保留）。规则：能力为假且带
`degradedNotice` 的，对应提示必须出现在界面，夹具不测界面但校验器要求四端生成常量里该键存在。
安卓、鸿蒙的值是当前假设，实现时以实测改契约，不改代码里的常量。

## 7. API

服务端仓手写 `mobile-v1.yaml`，OpenAPI 3.0.3（校验器 swagger-request-validator 对 3.0 支持最稳），覆盖：

- `/api/auth/sms-login/send-code`、`/api/auth/sms-login/verify`
- `/api/mobile/projects`（GET）、`/api/mobile/media`（POST multipart）、
  `/api/mobile/media/status`、`/api/mobile/media/usage`
- `components/schemas`：`RelayProject`、`MediaStatus`、`MediaUsage`、`CaptureManifest`
  （字段与 `CaptureManifest.swift` 一致，`tsaToken` nullable 预留）

服务端 `MobileApiContractTest`：`swagger-request-validator-mockmvc` 校验每个端点的真实响应，
Map 返回值不改也能被约束。桌面端调用的 `/api/mobile/inbox/*`、`/api/mobile/transfer/*`
同样进 YAML，但本期只校验手机端调用的那组。

移动仓 `contract/api/mobile-v1.yaml` 是副本；`PINNED.json` 记服务端 commit sha 与副本 sha256。
`pull-api.mjs` 从本机 checkba_cloud 仓（默认 `/Users/zewei/Documents/2024-2044/5-Tech/1-2 checkba_cloud`，
环境变量 `CHECKBA_CLOUD_DIR` 覆盖）拉最新并改写 `PINNED.json`，作为一次可见的 PR 改动。
四端**手写**请求代码对着 YAML，不生成客户端。API 夹具：每个端点一份样例响应，四端解码器测试用。

漂移防线：服务端测试保证「实现 = 服务端 YAML」；`check.mjs` 保证「副本 sha = PINNED」；
两份 YAML 由 PINNED 的 sha 关联。刷新副本是显式动作，不是静默同步。

## 8. 持久化与触发（C6）

规矩要在五个层面被触发，越靠前越便宜：

| 层 | 机制 | 触发时机 | 抓什么 |
|---|---|---|---|
| 会话加载 | 仓库根 `CLAUDE.md`「契约规矩」节（每个会话自动加载） | 任何会话开始 | 模型知道有契约、改动顺序、禁止内联 |
| 任务触发 | 项目级 skill `.claude/skills/contract-change/SKILL.md` | 任务涉及文案 / 令牌 / 状态 / 能力 / 接口 | 给出改契约的步骤：先改 contract 与夹具，再 gen，再四端 |
| 编辑即时 | `.claude/settings.json` PostToolUse 钩子 → `contract/tools/hook-post-edit.mjs` | Edit/Write 命中 `contract/**` 或生成物路径 | 立即跑 `check.mjs --quick`，失败 exit 2 把问题经 stderr 回灌会话 |
| 提交前 | git pre-commit（`npm run prepare` 安装） | `git commit` | `check.mjs` 全量 |
| 合并前 | `.github/workflows/contract.yml` | push / PR | `check.mjs` + `npm test`（含夹具适配测试） |
| 服务端 | `MobileApiContractTest` 进服务端 `ci.yml` | 服务端 PR | 实现偏离 YAML |

兜底：项目自动记忆一条 `contract-discipline`（type: feedback），指向 CLAUDE.md 该节；
`.github/pull_request_template.md` 加一行「改了契约？先 contract → gen → 四端」勾选。

CLAUDE.md 该节内容（定稿）：

> **契约规矩**（`contract/`，设计见 `docs/specs/2026-09-02-contract-design.md`）
> 1. 状态名、桶名、界面文案、设计令牌、能力开关、API 形状的**唯一来源**是 `contract/`。
> 2. 改动顺序：先改 `contract/*.json` 与 `contract/fixtures/`，跑 `node contract/tools/gen.mjs`，
>    再改各端行为代码；生成物进仓提交。
> 3. 取证主流程界面文案不许内联，一律走 `strings.json` 的键。
> 4. 提交前 `node contract/tools/check.mjs` 必须绿；CI 会再跑一次。
> 5. API 变更先改服务端仓 `openapi/mobile-v1.yaml` 并过 `MobileApiContractTest`，
>    再 `node contract/tools/pull-api.mjs` 刷新副本。
> 6. 新端（安卓、鸿蒙）从生成物起步，不存在手抄阶段；实现一个夹具适配测试再写第一屏。

## 9. 生成器与校验器

`gen.mjs`（Node 22，零依赖）读四个 JSON，输出：

| 端 | 路径 | 说明 |
|---|---|---|
| 小程序 | `miniprogram/styles/tokens.wxss` | 原地覆盖，头部标 GENERATED |
| 小程序 | `miniprogram/utils/contract/{strings,states,capabilities}.ts` | `phase.ts` 改为 import 这些常量 |
| iOS | `ios/Sources/Design/Tokens.swift` | 原地覆盖，保留 `T.L / T.D / T.S / T.Sp / T.Ty` 调用面 |
| iOS | `ios/Sources/Contract/{Strings,States,Capabilities}.swift` | `TransferState` rawValue 与别名从此生成 |
| 安卓 | `android/contract/src/main/kotlin/com/aiworkdeck/contract/*.kt` | 纯 Kotlin 模块，无 Android 依赖 |
| 鸿蒙 | `harmony/contract/src/main/ets/*.ets` | |
| 全部 | `CONTRACT_VERSION` 常量 | 各端启动日志打印 |

`check.mjs`：① 生成物与 JSON 一致（重新生成比对）；② 夹具合各自 JSON Schema；
③ `contract.json` 的 sha 清单与文件一致；④ `api/PINNED` 的 sha 与副本一致；
⑤ 四端源码不内联词典中的中文值（`--quick` 跳过⑤）。任一失败非零退出并列出差异。

## 10. 夹具与适配

夹具是黄金向量，平台无关。每端一个薄适配把夹具喂进自己的实现：

| 端 | 适配 | 运行 |
|---|---|---|
| 小程序 | `tests/contract.test.ts` | `npm test` |
| iOS | `ios/Tests/ContractFixturesTests.swift`，夹具目录作为测试 bundle 资源 | `xcodebuild test`（WorkdeckTests） |
| 安卓 | `android/contract/src/test/kotlin/ContractFixturesTest.kt` | Gradle test（客户端建立时） |
| 鸿蒙 | `harmony/contract/src/test/*.test.ets` | DevEco 单测（客户端建立时） |

`check.mjs` 自身有测试 `tests/contract-tools.test.ts`（坏夹具要红、生成物过期要红、内联文案要红）。

## 11. 迁移顺序

1. 建 `contract/` 与工具，先让 `check.mjs` 在**现状**上红出全部已知漂移。
2. iOS `TransferState.moving → uploading`，加解码别名；修首页计数标签。
3. 两端文案抽进词典；`Tokens.swift` 与 `tokens.wxss` 改为生成物。
4. 服务端 YAML + 契约测试；移动仓钉副本。
5. §8 五层触发全部落地；CLAUDE.md、skill、钩子、CI、记忆。
6. 安卓、鸿蒙客户端立项时直接引用生成物。

## 12. 不做

不做像素级布局规范。不生成 API 客户端。不重构服务端 `Map` 返回值。不做运行时拉契约。
不为平台化层（设置、导航）的文案建键。

## 13. 验证口径

- `node contract/tools/check.mjs` 在改造后的 main 上绿；在故意改坏一个令牌值后红。
- `npm test` 全绿，含夹具适配。
- `xcodebuild test -scheme Workdeck` WorkdeckTests 全绿，含夹具适配。
- 服务端 `mvn test -Dtest=MobileApiContractTest` 绿；改一个响应字段名后红。
- 新开一个 Claude 会话，只说「把已暂存改成已缓存」，会话应先改 `strings.json` 再 gen，
  而不是去改 Swift 或 TS 里的字面量。这是 C6 的验收。
