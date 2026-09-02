# AI Workdeck 移动端

现场取证拍摄、同步归档到项目目录、文件管理。两个原生端：

| 端 | 技术 | 发布主体 | 覆盖 |
|---|---|---|---|
| iOS | Swift / SwiftUI | Zhen Shan Mei Grace Legacy Limited（香港，Team `X9B97KVA84`） | 中国大陆以外全部区 |
| 微信小程序 | 原生 WXML / WXSS / TypeScript | 北京京微资易科技有限公司 | 中国大陆 |
| iOS 中国区 | 同上 | 北京京微资易科技有限公司（需单独开 Apple 账号 + App 备案） | 中国大陆 |

香港主体**无法**为大陆区 App Store 做 ICP 备案（港澳台在 MIIT 体系外），
所以大陆区必须用北京主体。这不是可选项。

## 场景

尽调现场需要拍摄资料、取证。手机拍完，照片自动归到你电脑上那个项目的
`现场影像/YYYY-MM-DD/` 目录里。

## 数据流

```
手机拍摄
  ├─ 原图写入应用沙盒（不进系统相册）
  ├─ 立即算 SHA-256，写入时间 / GPS / 设备型号
  └─ 生成 manifest（clientMediaId UUID + 预留 tsaToken 字段）
        ↓  客户端加密（项目密钥，云端拿不到明文）
  分块上传 → addin.aiworkdeck.com（复用 /api/files/{id}/upload）
        ↓  云端中转区：只存密文，7 天 TTL 兜底
  桌面端上线后拉取 → 解密 → 落到 localRoot
        ↓  桌面端 ACK 确认落盘 → 云端立即删除
  手机端标记「已落盘」（界面三段：上传中 / 已暂存 / 已落盘），本地原图不自动删，图集里手动删
```

删除由 **ACK 触发**，不由时间触发。7 天 TTL 只是兜底，两个机制不能混。

## 一致性口径

两端都原生，一致性不靠共享 UI 代码，靠共享契约（API 形状、状态机、文案词典、
设计令牌）。然后**分层**：

契约的机器形态在 `contract/`（真源）；改动规矩见根目录 `CLAUDE.md`。

- **逐像素一致**：取证拍摄流程（相机页、上传队列、归档确认）
- **各自平台化**：导航、设置、文件浏览（iOS 走 HIG，小程序走微信规范）

已知的能力差，不假装等价：

| | iOS | 小程序 |
|---|---|---|
| 后台上传 | `URLSession` 后台传输 | **不支持**，退出即停 |
| 录像时长 | 无限制 | `chooseMedia` 最长 60 秒（iOS），`startRecord` 最长 30 秒 |
| 毛玻璃 | `.ultraThinMaterial` 系统级 | `backdrop-filter`，安卓中低端机降级为实色 |
| 设备证明 | App Attest | 无 |

小程序端录像做**连续分段**，并在界面上明示「本端录像为记录用途，证据用途请用 iOS 端」。
分段对证据是瑕疵，不能默默降级。

## 小程序开发

```bash
npm install
npm run typecheck
```

用微信开发者工具打开仓库根目录。当前用 `touristappid`（测试号），
小程序注册完成后把 `project.config.json` 的 `appid` 换成正式 AppID。

自动化走查（IDE 需开启「设置 → 安全设置 → 服务端口」）：

```bash
npm run shot
```

会连上 IDE、截图当前页面到 `shot-index.png`。

## 目录

```
miniprogram/
  styles/tokens.wxss     设计令牌，单一来源
  styles/glass.wxss      毛玻璃与降级、浮现动效
  utils/layout.ts        顶部/底部安全区度量，全局算一次
  utils/capability.ts    毛玻璃能力探测
  utils/icons.ts         SVG 图标（内联 data URI，不用 emoji）
  components/nav-bar/    自定义导航栏（dark 属性给深色页）
  utils/phase.ts         传输阶段展示层：三段映射 / 计数 / 按日分段 / 删除文案（纯函数，tests/ 里有单测）
  pages/
    gallery/             图集：按项目看、按日分段、列数 / 视图切换、多选删除
ios/                     SwiftUI（待建）
docs/specs/              设计文档
```

## 两条踩过的坑

1. **`requiredPrivateInfos` 里写 `chooseMedia` 会让整个 app.json 编译失败**，
   而且 IDE 不报明显错误，表现为小程序永远起不来。那个字段只收位置类接口。
2. **图标 SVG 的颜色不要预先写成 `%23`**，`encodeURIComponent` 会二次编码成
   `%2523`，所有图标静默消失。写原始 `#` 即可。

## 顶部遮挡

所有导航高度来自 `utils/layout.ts` 的全局度量，页面**不许**自己调
`wx.getMenuButtonBoundingClientRect()`。安卓冷启动时该接口可能返回全 0，
度量层已做兜底并会 `console.warn`；真机上看到那条警告说明该机型要单独处理。

## 许可与商标

本仓库是 AI WorkDeck 一揽子开源项目的一部分，与内核仓库 [zeweihan/aiworkdeck](https://github.com/zeweihan/aiworkdeck) 遵循同一套安排：

- 代码以 **GNU AGPLv3** 发布（见 [LICENSE](LICENSE)）；商业许可由北京京微资易科技有限公司（海外发行：真善美承泽有限公司 Zhen Shan Mei Grace Legacy Limited）另行提供，见内核仓库的 [COMMERCIAL-LICENSE.md](https://github.com/zeweihan/aiworkdeck/blob/master/legal/COMMERCIAL-LICENSE.md)。
- 贡献适用内核仓库的 [CLA](https://github.com/zeweihan/aiworkdeck/blob/master/legal/CLA.md)（对贡献内容的双许可再授权集中于公司主体）。
- 商标：AI WorkDeck 标识（K 形图形）已在中国注册（第 9 类）；「AI WorkDeck」文字为商号与未注册商标（™），受反不正当竞争法保护——见 [TRADEMARKS.md](https://github.com/zeweihan/aiworkdeck/blob/master/legal/TRADEMARKS.md)。
- 治理与社区：见内核仓库 [GOVERNANCE.md](https://github.com/zeweihan/aiworkdeck/blob/master/GOVERNANCE.md)。
