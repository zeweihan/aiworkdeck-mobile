# 鸿蒙上架素材（华为 AGC）

`com.aiworkdeck.mobile.huawei` 在 AppGallery Connect 上架用的素材与规格。
文案母本在 `docs/specs/2026-09-13-store-assets-design.md` §5.4，截图叙事在 §2。

## 目录

| 路径 | 是什么 |
|---|---|
| `screenshots/` | 交 AGC 的成品截图（由 `scripts/store-shots/compose.mjs` 从原始屏合成） |
| `listing/` | 应用名称 / 简介 / 介绍 / 更新说明（待建，§5.4） |

原始屏（未合成）在 `scripts/store-shots/raw/harmony/zh-Hans/01..08.png`，
由 `scripts/store-shots/capture-harmony.sh` 在模拟器上截出，**模拟器原生 1256×2760**。

## AGC 当前规格（2026-09-13 查证）

华为文档站同一路径下新旧两套并存，**以下两页是 HarmonyOS NEXT 应用的现行标准**，
其余页面（尤其英文站）给的是 HarmonyOS 3.1/4.0 及以下的旧值，不要照抄：

- 《素材规范》（2026-09-08 更新）
  https://developer.huawei.com/consumer/cn/doc/app/agc-help-app-visual-asset-spec-0000002277607976
- 《应用文件要求》（2026-07-09 更新）
  https://developer.huawei.com/consumer/cn/doc/app/agc-help-connect-api-appendix-requirement-0000002271160693

两页数据一致。手机（HarmonyOS 应用）截图：

| 项 | 值 |
|---|---|
| 竖向截图 | 比例 9:16，**1080×1920** |
| 横向截图 | 比例 16:9，**1920×1080** |
| 数量 | 每个方向 **3–10 张**（本仓按 §2 出 8 张竖版） |
| 格式与大小 | PNG / JPG / JPEG **≤ 5 MB**；WEBP ≤ 200 KB（不允许动图） |
| 应用图标 | 1 张正方形，**216×216 或 1024×1024**；PNG ≤ 3 MB，或 WEBP ≤ 100 KB（不允许动图） |

同页还按设备类型分套，本项目暂时只上手机：平板 1920×1280 / 1280×1920（3–10 张），
PC-2in1 1920×1080（3–10 张），手表 840×840（4–8 张），
智慧屏 1920×1080（5–8 张，另需 4 张推荐图片）。

**旧值提醒**：英文站 *App File Restrictions*（2025-09-30 更新）与中文《应用文件要求》
`agcapi-file-requirement-0000001158365071`（2026-03-16 更新）里的 720×1280 / 1280×720、
3–5 张，是 HarmonyOS 3.1/4.0 及以下与 Android 应用的口径，**不适用本应用**。
中文那一页正文自己写明了这一点。

### 未查证

以下没在官方公开页面找到明确说法，不要当成事实用（2026-09-13 未登录 AGC 控制台的公开文档抓取）：

- 截图是否必须**按语言各出一套** 3–10 张，还是可以多语言复用同一套。
- 除 1080×1920 / 1920×1080 之外是否接受其他等比例分辨率（如 1080×2340 这类新机型比例）；
  文档只给单一分辨率，没写容差。因此 `compose.mjs` 出 AGC 版时按 1080×1920 缩放。
- HarmonyOS NEXT 手机应用是否对折叠屏 / 车机另有截图规格（这两类在现行《素材规范》里没有独立分类）。
- 应用简介 / 应用介绍的字数上限（§5.4 标的「子代理核实各字段上限」仍待办）。
- AGC 控制台「应用信息 → 应用截图」的实际交互（是否有分辨率容差、是否强制按语言切换）——
  要登录后台才看得到。

## 原始屏怎么截

```bash
/Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator -start "Pura 90 Pro"
scripts/store-shots/capture-harmony.sh            # 八屏
scripts/store-shots/capture-harmony.sh --screen 6 # 只重截一屏
```

脚本靠 debug-only 的 `ScreenshotMode`（`harmony/entry/src/main/ets/ScreenshotMode.ets`）
把模拟器摆成可截图的样子：跳过服务端会话、取景区贴静态现场照、定位固定 ±5 米、
选项目页给三条演示项目、`filesDir/FieldEvidence` 摊 16 件影像。

**种子素材进包**是这一端独有的：`hdc shell` 是 uid 2000，`hdc file send` 往
`/data/app/el2/100/base/com.aiworkdeck.mobile.huawei/haps/entry/files/` 写一律
permission denied（2026-09-13 实测，目录本身是 777 也一样，挡在 SELinux/父目录那层），
所以现场照片缩成 720 宽副本放进 `entry/src/main/resources/rawfile/shots/` 随包走。
代价是这批素材（约 1 MB）也在 release HAP 里——**读它的代码路径是 debug-only，字节不是**。
真要把这 1 MB 从发行包里摘掉，得给 hvigor 配按 buildMode 分的资源目录，另开一张卡。
