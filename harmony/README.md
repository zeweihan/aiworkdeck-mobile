# harmony/ — HarmonyOS NEXT 客户端（ArkTS）

设计：`docs/specs/2026-09-03-harmony-client-design.md`（沿用安卓 `2026-09-02-android-client-design.md`）。
dev-board [#391](https://github.com/zeweihan/dev-board/issues/391)、[#407](https://github.com/zeweihan/dev-board/issues/407)。

包名 `com.aiworkdeck.mobile.huawei`，单 product `default`，服务端 `https://addin.aiworkdeck.com`。

## 工程结构

| 模块 | 是什么 |
|---|---|
| `contract/` | HAR。四端共享契约的 ArkTS 生成物（`contract/tools/gen.mjs` 产出，**不要手改**），`Index.ets` 汇出 |
| `entry/` | HAP。`src/main/ets/` 按 `model / services / design / pages` 分层 |

`entry` 通过 `oh-package.json5` 的 `"contract": "file:../contract"` 依赖 HAR，代码里 `import { T, ContractStates, ContractStrings, ContractCapabilities } from 'contract'`。

领域层（`entry/src/main/ets/model/`、`design/L10n.ets`）是**不引 `@ohos.*` / `@kit.*` 的纯 ArkTS**，
仓库根的 `npm test` 通过 `scripts/node-ts-resolve.mjs` 直接跑它们（`.ets` 用 `typescript.transpileModule`
转译，裸说明符 `contract` 映射到 `harmony/contract/Index.ets`）。CI 只跑这一层，hvigor 构建靠本机。

## 构建（不开 IDE）

```bash
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node
cd harmony
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install --all      # 首次
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug --no-daemon
```

产物（未配签名时）：`entry/build/default/outputs/default/entry-default-unsigned.hap`。
`hvigorw` 带 ArkTS 语法检查，编不过就是没遵守 ArkTS 约束（spec §3）。

本机环境（2026-09-03 实测）：DevEco Studio 26.0.0，HarmonyOS SDK API 26（`platformVersion 26.0.0`，
`version 26.0.0.105`），hvigor / hvigor-ohos-plugin 6.26.4。

## 版本字符串（都是踩出来的，别凭印象改）

| 位置 | 值 | 依据 |
|---|---|---|
| `build-profile.json5` `compatibleSdkVersion` | `"5.0.0(12)"` | hvigor 明说：**API 10–25 必须写 `'5.0.0(12)'` 这种带括号的形式**。写 `"12"` 会报 `00306042 Specification Limit Violation` |
| `build-profile.json5` `targetSdkVersion` | `"26.0.0"` | 同一条错误信息的下半句：**API 26 及以后必须写 `'26.0.0'`，不带括号**。写 `"26.0.0(26)"` 会报 `00308018 api version parameter is illegal` |
| `hvigor/hvigor-config.json5` 与 `oh-package.json5` 的 `modelVersion` | `"6.0.6"` | hvigor 只校验**这两处一致**（不一致报 `00303027`，让你走 Migrate Assistant），不校验具体值。若日后 DevEco 打开工程提示迁移，以 IDE 写入的值为准，两处一起改 |
| `build-profile.json5` `useNormalizedOHMUrl` | `true` | stage 模型 + API ≥ 12 的模板默认值，本机构建通过 |
| `contract/Index.ets` | `export * from './src/main/ets/…'` | ArkTS 接受 `export *`，不必逐个具名导出 |

`contract` 这个 HAR 模块在根 `build-profile.json5` 的 `modules` 里**不写 `targets.applyToProducts`**——
HAR 不独立安装，写了 hvigor 会警告 `HAR modules cannot be installed independently`。

## ArkTS 与契约生成物

ArkTS 严格模式的两条在生成器里踩过：

1. `as const` 不认（arkts-no-as-const）→ 生成物改成显式 `interface` + 类型化 `export const`。
2. 对象字面量必须对应显式类型（arkts-no-untyped-obj-literals）→
   - 接口字段里的**嵌套 `Record<string, string>` 字面量不认**，得提成同文件里的具名常量再引用；
   - `Record` 字面量的**键必须是字符串字面量**（`"moving": "uploading"`），写成标识符键就当成无类型对象字面量。

这两条都做在 `contract/tools/lib.mjs` 的 ArkTS 渲染段里。改契约的流程照旧：
改 `contract/*.json` → `node contract/tools/gen.mjs` → 改各端代码 → `node contract/tools/check.mjs`。
`check.mjs` 会扫 `harmony/entry/src/main/**/*.ets` 的内联中文文案（一律走 `tr(key)`），
也会扫 `harmony/build-profile.json5` 里的签名口令。

## 签名（用户动作，不进仓）

`build-profile.json5` 的 `signingConfigs` **保持 `[]`**（spec H11）。

- 调试签名（一次）：DevEco 打开 `harmony/` → 登录华为开发者账号 →
  File › Project Structure › Signing Configs › Automatically generate signature。
  生成的材料在 `~/.ohos/config/`，DevEco 会往 `build-profile.json5` 写一段 `signingConfigs`——
  **这段不要提交**，`contract/tools/check.mjs` 扫到 `storePassword` / `keyPassword` 就红。
- 发布签名：`~/.aiworkdeck/harmony/` 下的 `.p12` + AGC 发布证书 + 发布 Profile（`.p7b` 待建），
  配到 `signingConfigs.release` 后 `hvigorw assembleApp -p buildMode=release` 出 `.app` 交 AGC。
  出包脚本另卡。

## 模拟器（用户动作，未就绪）

本机**没有下载系统镜像**（`~/Library/Huawei/Sdk` 不存在），也没有调试签名，所以现在只能编译，装不了。
用户在 DevEco Device Manager 里下载 phone 镜像（HarmonyOS 7.0.0(26.0.0)，Pura 90 Pro 实例已建）并接受许可后：

```bash
Emulator -start "Pura 90 Pro"
hdc list targets
hdc install <hap>
hdc shell aa start -a EntryAbility -b com.aiworkdeck.mobile.huawei
hdc shell snapshot_display -f /data/local/tmp/x.jpeg && hdc file recv /data/local/tmp/x.jpeg .
```

## 已知限制

- 首版不建 DevEco 本地测试（hypium）；领域层测试在仓库根 `tests/harmony/`。
- 实况窗（Live View Kit）留卡：`event` 只能取固定场景（最接近的是 `TIMER`），且每个场景要在 AGC 申请权限，
  未获批调用报 `1003500005`。首版录音常驻展示用长时任务的系统通知。
- 存相册默认关；无 `ohos.permission.WRITE_IMAGEVIDEO`（受限权限，须 AGC 申请 ACL）时只能走
  `photoAccessHelper.showAssetsCreationDialog` 系统确认弹窗。
