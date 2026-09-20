# 商店截图合成管线

把各端的**原始屏**（未合成的纯截图）加上标题、副题和设备边框，出成各商店要求的尺寸。
规格：`docs/specs/2026-09-13-store-assets-design.md` §2（叙事）§3（视觉）§4（尺寸与落地）§8（验收）。

## 一条命令重出全套

```bash
# iOS：1320×2868 → fastlane/screenshots/<locale>/NN.png
node scripts/store-shots/compose.mjs --end ios --locale zh-Hans
node scripts/store-shots/compose.mjs --end ios --locale en-US

# 安卓：1080×2400 → android/store/screenshots/phone-1080x2400[-en-US]/NN-<slug>.png
node scripts/store-shots/compose.mjs --end android --locale zh-Hans
node scripts/store-shots/compose.mjs --end android --locale en-US

# 鸿蒙：1080×1920（AGC 手机竖版）→ harmony/store/screenshots/phone-1080x1920[-en-US]/NN-<slug>.png
node scripts/store-shots/compose.mjs --end harmony --locale zh-Hans
node scripts/store-shots/compose.mjs --end harmony --locale en-US

# 安卓宣传图：1024×500 → android/store/feature-graphic-1024x500-{zh,en}.png
node scripts/store-shots/compose.mjs --feature --locale zh-Hans
node scripts/store-shots/compose.mjs --feature --locale en-US

# 微信开放平台「应用运营流程图」：安卓真机截图串 2400×1138
# → android/store/wechat-open/operation-flow-screens.png
node scripts/store-shots/compose.mjs --flow
```

可选参数：

- `--out <dir>`：改落地目录（预演、试排版用）。
- `--raw <dir>`：改原始屏目录，默认 `scripts/store-shots/raw/<end>/zh-Hans/`。

**en-US 复用 zh-Hans 的原始屏**，只换标题与副题——App Store 两个语言的截图组只要求各 8 张，
界面本身目前只有简体中文（描述末段已声明）。

## 目录

```
scripts/store-shots/
  captions.json        §2 那张表的结构化版本；改文案只改这里
  templates/frame.html 合成模板（深绿渐变底 + 标题 + 设备边框）
  templates/flow.html  微信开放平台运营流程图模板（真机截图横排 + 箭头 + 步骤文字）
  compose.mjs          合成脚本
  png-rgb.mjs          把 Chromium 的 RGBA PNG 重编码成无 alpha 的 RGB PNG
  raw/<end>/zh-Hans/   各端原始屏 NN*.png（capture-*.sh 产出）
  assets/scenes/       现场照片（灌数据用，见下）
  seed/                各端灌数据 manifest 模板
  out-preview/         预演产物，已在 .gitignore
```

## 尺寸表

| 端 | 目标尺寸 | 落地目录 | 文件名 |
|---|---|---|---|
| iOS（App Store iPhone 6.9 吋） | 1320×2868 | `fastlane/screenshots/zh-Hans/`、`fastlane/screenshots/en-US/` | `NN.png` |
| 安卓（Google Play / 国内六家） | 1080×2400 | `android/store/screenshots/phone-1080x2400/`（zh-Hans）、`…-en-US/` | `NN-<slug>.png` |
| 鸿蒙（华为 AGC 手机竖版） | 1080×1920（9:16） | `harmony/store/screenshots/phone-1080x1920/`、`…-en-US/` | `NN-<slug>.png` |
| 安卓宣传图 | 1024×500 | `android/store/` | `feature-graphic-1024x500-{zh,en}.png` |
| 微信开放平台运营流程图 | 2400×1138 | `android/store/wechat-open/` | `operation-flow-screens.png` |

> 鸿蒙 1080×1920 的出处是 `harmony/store/README.md` 的「竖向截图」一行（AGC 手机口径，
> 不是那份 README 里提到的模拟器原生 1256×2760，也不是旧文档里的 720×1280）。
> 原始屏 1256×2760 会按比例缩进设备边框，不拉伸。

> 微信开放平台那张是**真机截图串**，不是框图——官方对「App 运行流程图」的定义就是
> 「App 装到手机后运行起来的界面截图」。步骤顺序与文案在 `compose.mjs` 的 `FLOW_STEPS`，
> 版式在 `templates/flow.html`，详见 `android/store/wechat-open/README.md`。

输出 PNG **一律不带 alpha 通道**（App Store 拒收带透明通道的截图）。自检：

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha fastlane/screenshots/zh-Hans/01.png
```

## 换现场照片后重跑

`assets/scenes/` 下是灌进 App 里当演示影像的现场照片（档案室 / 卷宗特写 / 会议室 / 车间 /
工地 / 仓库 / 楼外立面 / 设备铭牌，不出现可辨识人脸、真实公司名与门牌）。整目录可替换，
文件名保持 `01..08`。替换后：

1. 重跑对应端的 `capture-*.sh` 重出原始屏到 `raw/<end>/zh-Hans/`；
2. 重跑上面那几条 `compose.mjs` 命令。

只改文案不用重截原始屏，改完 `captions.json` 直接跑 `compose.mjs` 即可。

## 视觉

- 底色采样自 `docs/design/app-icon-1024-dark-green.png`：
  主色 **`#2E5A50`**（图标底），点缀 **`#89A8A0`**（图标笔画，东方清雅配色 dev-board#731）。
  页面渐变上浅下深 `#4C8576 → #2E5A50 → #254A41`（主色提亮 / 主色 / 主色压暗，不用纯黑），
  顶部叠一层薄荷径向光晕。三个值都写在 `templates/frame.html` 的 `:root` 里。
- 设备边框：iOS 画 iPhone 17 Pro Max 风格圆角 + 灵动岛胶囊（自己画，没用 Apple 官方 bezel 素材）；
  安卓 / 鸿蒙用通用圆角 + 顶部居中打孔。边框尺寸由原始屏的真实宽高比算出，**截图 1:1 不拉伸**。
- 设备区占画面高度 72%，贴底留 2.1% 余量，标题区在上方。
- 字体：中文 `PingFang SC`；英文 `SF Pro` / `Inter`，本机没装时回退 `system-ui`（macOS 上即 SF）。
  实测本机只有 PingFang SC 与 system-ui，英文实际渲染的是 system-ui = San Francisco。
- 标题排版：同一端同一语言先量 8 张、取最小字号统一渲染，保证一组图字号一致。
  主标题最多 2 行、副题最多 2 行，超了自动缩字号；仍然放不下就直接报错停下，不会截断。
  中文自动断行会把词切开（「一部手机，服/务所有在办项目」），所以 `captions.json` 里
  允许写 `\n` 手动指定断点（模板用 `white-space: pre-wrap` 原样保留），一般断在逗号后。
  英文靠 `text-wrap: balance` 自动配平，不用手动断。

## 依赖

`playwright-core@1.62.0`（devDependency，`npm ci` 装）。它对应的 Chromium revision 是 **1234**，
本机 `~/Library/Caches/ms-playwright/chromium_headless_shell-1234` 已有，不需要再下载浏览器；
浏览器二进制不进仓。换 playwright 版本前先确认缓存里有对应 revision，否则要联网下载。
