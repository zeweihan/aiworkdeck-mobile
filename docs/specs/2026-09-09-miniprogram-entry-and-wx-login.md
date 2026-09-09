# 小程序：设置页与充值入口纠正（dev-board#535）+ 微信手机号一键登录（dev-board#534）

日期 2026-09-09。起因：第二期上线后用户实测「充值在哪？设置在哪？登录为什么还要收验证码？」。
根因是 `2026-09-09-miniprogram-virtual-payment-plan.md` §5 把充值入口写成「余额行可见时才渲染」，
而余额对没有官网账户的用户是 NOT_CONNECTED、整行不渲染；且小程序没有设置页。

## 0. 用户路径（这一节是验收标准，做完必须从首页逐步走通并截图）

| 状态 | 首页 | 「我的」页 | 充值页 |
|---|---|---|---|
| 未登录 | 进首页即跳登录页；登录页首屏是「微信手机号一键登录」大按钮，下方折叠「用短信验证码登录」 | — | — |
| 新用户（无官网账户，NOT_CONNECTED） | 右上角齿轮 → 我的 | 手机号、余额行显示 `balance.notConnected` 措辞、**充值按钮可见** | 三档可选，可支付 |
| 老用户（有余额） | 同上 | 余额 ¥xx.xx、充值按钮 | 同上 |
| 审核账号 / 本服务器未开通（REVIEW_ACCOUNT / DISABLED） | 同上 | 余额与充值**都不渲染**，只有手机号与退出登录 | 不可达 |
| 上游故障（UNAVAILABLE 等） | 同上 | 余额行 `balance.unavailable`，**充值按钮仍可见** | 可进，下单失败按信封 message 提示 |

## 1. 「我的」页（本仓 `miniprogram/pages/settings/settings`）

- 首页顶栏右侧、上传队列统计旁加一个齿轮图标按钮（`aria-label` 用 `settings.title`），点进 `/pages/settings/settings`。
- 页面内容自上而下：账户（手机号脱敏 `138****0000`，取自登录时保存的手机号；没有就显示 `settings.account`）、
  统一账户余额行 + 「充值」按钮（规则见 §0 表）、退出登录（从项目页**迁**到这里，项目页删掉退出登录与余额行，
  只保留项目列表）、版本号（小程序版本从 `wx.getAccountInfoSync().miniProgram.version`，体验版为空则显示 `settings.devBuild`）。
- 余额行与充值按钮的渲染规则改在契约里钉死（§3），页面按 `kind` 分支，不匹配 message。
- 充值页返回时「我的」页 `onShow` 重新拉余额。

## 2. 微信手机号一键登录（三仓）

- **官网**：`/api/internal/account` 新 action `wx-phone`：`{action:"wx-phone", code}` → `wxGetPhoneNumber(code)` →
  `200 {phone}`（`normalizePhone` 后的大陆号）；非 86 → `400 unsupported_region`；code 无效 → `401 invalid_wx_code`；
  未配小程序 AppSecret → `503 wx_not_configured`。**不建官网账户**、不发赠额（与公开路由 `/api/auth/wx-phone` 的区别）。
- **Java**：`POST /api/auth/wx-phone-login {code}`（匿名）：经 `MobileBillingClient` 同一套 base-url/secret 调上面的 action
  换手机号 → `userService.findOrCreateByPhone(phone)` → `userSessionService.issue` → 响应与 `sms-login/verify` 完全同形
  （`LoginResult`）；走 `authAbuseGuard` 的登录频控。未配 `mobile.billing.*` → code 1
  message「本服务器未开通微信一键登录，请用短信验证码登录」（无 kind）；官网 401 → code 1「微信授权已过期，请重试」；
  400 unsupported_region → code 1「目前仅支持中国大陆手机号」。`mobile-v1.yaml` 加端点，`MobileApiContractTest` 覆盖。
- **小程序**：登录页首屏 `button open-type="getPhoneNumber" bindgetphonenumber`（文案 `login.wxPhone`），
  拿到 `e.detail.code` 后调 `wxPhoneLogin(code)`（`utils/api.ts` 新增，成功路径与 `verifyLoginCode` 相同：存 session、跳首页）。
  失败 code 1 → toast message 并展开短信登录表单。用户拒绝授权（`errMsg` 含 deny）→ 不提示错误，展开短信表单。
  短信登录保留，折叠在「用短信验证码登录」下。

## 3. 契约改动（先改 `contract/`，再 gen）

- `schema/billing.schema.json` 说明段的 UI 映射加一条：**有充值能力的端（`CAPS.recharge` 非 false）**，
  NOT_CONNECTED 渲染余额行、文案 `balance.notConnected`，并显示充值入口；充值入口只在 DISABLED / REVIEW_ACCOUNT 收起。
  无充值能力的端维持原规则（整行不渲染）。
- `strings.json` 新键：`settings.title`（我的 / Me）、`settings.account`（账户 / Account）、`settings.version`（版本 / Version）、
  `settings.devBuild`（开发版 / Dev build）、`login.wxPhone`（微信手机号一键登录 / Sign in with WeChat phone number）、
  `login.useSms`（用短信验证码登录 / Sign in with SMS code）、`recharge.openHint`（充值后即开通统一账户 / Topping up opens your unified account）。
  `balance.notConnected` 已有，措辞不改。
- `capabilities.json` 不动。

## 4. 验收（缺一不可）

1. `npm run typecheck && npm test && node contract/tools/check.mjs` 绿。
2. 微信开发者工具里从**首页**出发截图四张：登录页首屏、首页右上角齿轮、「我的」页（NOT_CONNECTED 态也要有充值按钮）、充值页。
   automator 连不上就用 `cli open` 打开项目后走手动截图路径（`cli` 的 `--auto-port` 需要开发者工具「设置 → 安全设置 → 服务端口」已开）；
   实在截不了，汇报第一句写「未截图」，主会话另想办法，**不得默认通过**。
3. Java：`MobileApiContractTest`、`AuthController` 相关测试绿；官网：`verify-*.mts` 覆盖 `wx-phone` 三种失败。
