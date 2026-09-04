# 手机端给统一账户充值 — 设计与开通清单

调研日期 2026-09-04。看板卡 dev-board#425（服务端通路）/#426（iOS 内购）/#427（小程序虚拟支付）/
#428（安卓）/#429（四端界面）。本文是这五张卡共同的设计源。

结论先行：**能做，但四端的支付通道被各自平台的强制条款钉死，不存在一套通吃的实现**；
而且**渠道抽成会吃掉大部分毛利，国际版 iOS 在当前费率下是亏的**——这是本次最重要的发现。

---

## 1. 渠道经济性（决定做不做、先做哪端）

Credits 是 1 元充值 = 100 分 Credits，1:1 到账，充值侧不赚钱；毛利全部产生在消费侧：
AI 对话按 `exchangeRate 7.3 × marginMultiplier 1.2` 折算（名义毛利 ≈16.7%），
平台网关服务加价 1.2 倍（ASR 33%、OCR 17.5%、检索 28%）。
**综合毛利率约 15%~25%，取中位数即：用户充 100 元、花光，我们赚约 20 元。**

各渠道抽成与净利（按充 100 元、COGS 80 元测算）：

| 端 | 通道 | 平台抽成 | 我们净收 | 净利 |
|---|---|---|---|---|
| 网页 / 桌面（现状） | 微信 Native 扫码 / Stripe | ~0.6% / ~3% | 99.4 / 97 | +19 |
| 安卓 App | 微信支付 APP 支付 | ~0.6% | 99.4 | **+19** |
| 小程序（安卓/鸿蒙/Windows） | 微信虚拟支付 | 1%（标准 10%） | 99 | **+19** |
| 小程序（iOS） | 微信虚拟支付 → Apple | 12% | 88 | +8 |
| iOS App 大陆版 | Apple IAP | 实测净收 **84.24%** | 84.2 | +4 |
| iOS App 国际版 | Apple IAP | 实测净收 **70.0%**（标准 30% 档） | 70 | **−10（亏）** |

净收比例是 2026-09-04 用 App Store Connect REST API 直接读两个 App 的 price point
`proceeds/customerPrice` 得到的实测值，不是推算：大陆版三档一律 0.8424，国际版三档一律 0.7000。

**由此得到两条硬结论：**

1. **国际版必须先申请 App Store 小企业计划**（30% → 15%，净收 70% → 85%），
   否则 iOS 国际版充值每笔都在亏钱。这是本次投入产出比最高的一个动作，且是纯后台操作。
2. **大陆版当前 84.24% 的净收已经落在优惠档**（Apple 2026-03-15 起大陆区标准 25%、
   优惠档 12%），薄利但为正，可以直接做。

> 注：小程序在 iOS 上走微信虚拟支付（12%）反而比 iOS 原生 App 便宜。但**不能**在 iOS App 里
> 引导用户去小程序充值，那构成 App Store 3.1.3 禁止的站外购买行动号召。

---

## 2. 各端支付通道裁定

### 2.1 iOS（大陆版 + 国际版）：只能 Apple IAP

- App Store 审核指南 3.1.1：App 内解锁功能的额度充值必须走 IAP；3.1.2(a) 明确把 SaaS 列入适用对象。
- 逐条核对 3.1.3(a)–(g) 六类豁免，AI WorkDeck 的 AI 额度充值没有一类能套用。
- **一旦在 App 内出现充值入口——哪怕只是一个跳转外部浏览器的按钮或一句「去官网充值」的文案——
  就必须走 IAP**。3.1.3 总纲：非美国店面禁止任何指向非 IAP 支付方式的行动号召。
- External Purchase Link Entitlement 只覆盖美国、欧盟、韩国、荷兰（交友类）、日本，**不含中国大陆**。
- 硬约束：**IAP 购买的 Credits 不得设置过期时间**（3.1.1 原文）。我们 `topup` 池本就永不过期，兼容。
- 现状是「免费 App + App 内零购买」，这个状态本身合规，但它不是一个稳固的安全港
  （3.1.3(f) 的四个例子在审核实践中被当作穷尽列举），只是至今没被挑战。

**推论：iOS 端要么上 IAP，要么连「余额不足，请去官网充值」这句话都不能写。**
只展示余额、消耗余额是允许的。

### 2.2 微信小程序：只能微信虚拟支付，且不许跳出去付

- 微信《虚拟支付业务运营指南》把「工具类小程序增加使用次数/额度」和「AI 服务付费购买额度」
  逐字列为必须接虚拟支付的典型场景，我们的 Credits 充值正落在里面。
- 2026-02-27 公告要求虚拟支付业务在 2026-04-01 前完成全终端接入，该期限已过。我们目前
  小程序内没有任何支付功能，所以不违规；但**一旦做充值，第一天就必须直接上虚拟支付**。
- 运营指南第 4 条：纯虚拟类目的小程序，平台会**主动关闭其安卓端普通微信支付能力**。
  「先用普通 JSAPI 上线、以后再补」这条路技术上跑不通。
- 运营指南第 1 条另有一条独立禁令：**不得引导至 App、公众号、H5、个人号、网站完成支付**。
  所以小程序也不能用「跳官网充值」绕开。
- 技术形态：客户端 `wx.requestVirtualPayment`，服务端调微信的 `/xpay/*` 系列，
  发货靠 `xpay_goods_deliver_notify` / `xpay_coin_pay_notify` 推送 + `query_order` 轮询双保险。
  签名两把：`paySig = hmac_sha256(appKey, uri + '&' + body)`（appKey 不能下发前端，必须后端代算）、
  用户态 `signature = hmac_sha256(session_key, body)`。
- **代币 vs 道具**：选**道具（goods）**。代币的兑换比例一旦发布不可修改，而我们的 Credits 是
  「1 元 = 100 分」的货币面值模型，用道具按固定档位售卖（50/100/300 元）更贴合，也避免被
  兑换比例锁死。
- iOS 端额外前置：微信客户端 ≥8.0.68、iOS ≥15、仅大陆 App Store 账户、最低 1 元、
  且必须在公众平台配好「小程序简称」（Apple 支付要展示 display name）。iOS 端**没有沙箱**。

### 2.3 安卓原生 App：微信支付 APP 支付（+ 可选支付宝）

- 华为应用市场：强制走 IAP Kit 只绑定「联运」合作与游戏品类；非联运独立发行的工具类 App
  用微信/支付宝不违反现行审核指南（6.4 条是「推荐」而非强制）。
- **应用宝是风险点**：其审核规范有「应用接入涉及支付功能需接入腾讯支付，第三方支付可能被拒」
  的表述且不限品类，提审前必须用测试包实测。小米留有一条旧规范要求付费项联系商务，同样待验。
- Google Play：美国已因法院禁令（2025-10-29 生效）不再强制 Play Billing；其余地区按
  Expanded Billing Choice 时间表分批开放。国际版安卓另行评估。
- **微信支付 APP 支付可以现在就申请**：开放平台移动应用登记（包名 + 签名）审核 1–7 工作日，
  商户平台申请 APP 支付权限审核 7 个工作日内；材料里的「应用商店下载链接」可以用**已上架的
  iOS App Store 链接**满足，不需要安卓包先上架。这条不必和安卓上架串行排期。

### 2.4 鸿蒙：推迟

鸿蒙客户端目前只有契约生成物、没有任何业务代码。充值不单独排期，随客户端本体走。

---

## 3. 服务端架构

### 3.1 现状（三处必须先说清楚）

- **余额权威只在官网仓 aiworkdeckweb**：`credit_lots`（批次记账，`topup` 永不过期 / `reward` 24 个月）
  + `wallet_ledger`，金额一律整数分，币种由部署站点决定。结算唯一入口 `lib/payments/settle.ts`
  的 `settleFromChannel()`，比对 channel / currency / amountMinor 三项才落账。
- **手机端登录的是 Java 云后端**（addin.aiworkdeck.com），`X-Session-Id` 会话，
  经 `UserService.findOrCreateByPhone` 建的是 Java 本地用户，**与官网账户是两个身份空间**。
  一个只用手机端登录、从没连过桌面的用户，在官网侧根本没有账户，也就没有余额。
- **Java 后端现有 `/api/account/recharge` 绝对不能复用**：它的账户状态是机器级单例文件
  `~/.aiworkdeck/account.json`，云上 server 模式被 `MachineAccountGuard` 限制为仅 admin，
  且 admin 充的是「这台服务器连的那个账户」，语义上是错的。

### 3.2 选定方案：窄权限内部记账口（方案 C）

否决的方案 A（手机端自己持 `awdk_` Bearer 直连官网）理由：
- `awdk_` 是**该账户无范围限制**的凭据——能读余额与流水、能直接花 Credits 买 SKU、
  能取该用户的 OpenRouter runtime key 明文。放进手机 Keychain 等于把这个风险面扩到新设备类型。
- 官网 `api_keys` 表有 `MAX_ACTIVE_KEYS = 3` 上限，满槽淘汰最旧一枚。手机端每次登录换一把
  就会挤掉桌面端正在用的那把，表现为桌面端无预警掉线（详见 §6 已发现的存量缺陷）。
- `/api/auth/exchange-key` 不接受「拿现有会话换 Key」，必须重交手机号+验证码，
  等于让已登录用户再走一次短信验证。

选定形状（照抄已在生产验证的 `/api/internal/transfer` 模式）：

```
官网新增 app/api/internal/account/route.ts
  鉴权：X-Internal-Secret 恒定时间比较 + 仅 127.0.0.1；未配置或不符一律空体 404（不是 401/403）
  另起一把 secret，不复用 AWD_TRANSFER_BILLING_SECRET
  action = resolve         { phone | email } -> { accountId }
  action = create-recharge { accountId, amount(整数分), idempotencyKey } -> 同 /api/payment/create 的返回
  action = query           { accountId, outTradeNo } -> 同 /api/payment/query 的返回
  action = balance         { accountId } -> { balanceCents, plan }
```

Java 后端侧：
- `account_binding`（`user_id` ↔ 官网 `external_account_id`）继续做唯一映射表；
  手机端会话 → `findByUserId` → 无绑定则用**本次登录已验证过的**手机号/邮箱调 `resolve` 建绑定。
- **红线**：`resolve` 只能在 Java 后端已经校验过验证码之后调用，且手机号/邮箱只能取自
  服务端会话对应的 User 实体，**绝不接受请求体传入**——否则等于开了一个手机号枚举/任意建号的口子。
  这条与 `MobileTransferService.requireAccountId()` 现有做法一致（accountId 严格来自绑定表）。
- 多租户纪律沿用 `licensing-billing.md` 第 17 条：缺身份一律拒绝，**不回落机器级**。
  充值涉及真金白银，比 AI 额度更不能有「拿错账户扣钱」的回落分支。

### 3.3 幂等

- 官网 `orders` 表已有 `UNIQUE(userId, idempotencyKey)`，直接复用。
- **手机端必须自己生成并持久化 `idempotencyKey`**（发起充值前落盘，扛得住 App 被杀），
  不能照抄桌面端 `AccountController.recharge` 每次 `UUID.randomUUID()` 现生成的写法——
  那等于不带幂等键，弱网重试会在库里留下一串各自绑定独立二维码的悬挂 pending 单，
  而仓库里**没有**针对充值 pending 订单的过期回收任务。

---

## 4. iOS IAP 详细设计

### 4.1 商品（已通过 ASC REST API 建好）

| App | productId | 类型 | 基准价 | 状态 |
|---|---|---|---|---|
| 大陆版 6803309103 | `credits.cny.50` / `.100` / `.300` | 消耗型 | ¥50 / 100 / 300（CHN） | MISSING_METADATA |
| 国际版 6802233845 | `credits.usd.10` / `.20` / `.50` | 消耗型 | $10 / 20 / 50（USA） | MISSING_METADATA |

六个商品的本地化名称、描述、基准价格计划均已设好。**唯一卡住提审的缺项是审核截图**
（`appStoreReviewScreenshot` 全为 null），必须等 App 内充值界面做出来后截图上传。
销售地区（`inAppPurchaseAvailability`）返回 404 属正常初始态，非提审阻塞项，但 Apple 批准前必须设。

App ID 侧无需改动：两个 bundle id 的 `bundleIdCapabilities` 均为空，内购是默认能力，
**不需要重新签发描述文件**——这点对大陆版尤其重要，其 Distribution 证书已与 App 备案绑定，
重签会牵动备案变更。

### 4.2 服务端接入

- 新增支付通道：`lib/payments/types.ts` 的 `PaymentChannelId` 扩为 `'wxpay' | 'stripe' | 'appstore'`，
  在 `lib/payments/index.ts` 的 `ADAPTERS` 注册 `appstoreAdapter`。
  **不要动 `getPaymentAdapter()`**（部署级常量，刻意不按请求判定）；IAP 建单走独立新路由。
- **币种是坑**：苹果 JWS 里的 `price`/`currency` 是买家 storefront 的本地币种（可能是 JPY/EUR），
  直接塞进 `ChannelSettlement` 会被 `settle.ts:54` 的 `currency_mismatch` 全部打回，
  用户付了钱拿不到 Credits。做法：新建 `lib/payments/appstore-catalog.ts` 维护
  `productId → 站点币种面值` 的固定表，settlement 取面值与站点币种；苹果实收的
  `price/currency/storefront` 只作为对账字段写进 order，不参与三重校验。
  这与 `wxpay-adapter` 硬编码 `'CNY'`、`stripe-adapter` 强制 `'usd'` 的既有模式一致。
- **订单挂钩**：StoreKit 2 只有 `appAccountToken`（必须是 UUID）能可靠原样回传到
  `JWSTransactionDecodedPayload`。建单时生成 UUID 落进已有的 `orders.providerRef` 列
  （`idx_orders_provider` 索引已存在），iOS 端购买时经 `Product.PurchaseOption.appAccountToken(_:)` 传同一个值。
- **`queryCharge` 只能返回 null**：App Store Server API 所有查询端点都要 transactionId /
  originalTransactionId，没有任何端点支持用 `appAccountToken` 反查交易；建单时还没有 transactionId。
  `types.ts` 的契约允许「本通道无从回查返回 null」，`stripe-adapter` 已有先例。
  到账确认只能靠客户端回传 JWS + Server Notifications V2 两条路。
- **JWS 校验用官方库** `@apple/app-store-server-library`（npm 最新 3.1.0，Node 16+），
  `SignedDataVerifier.verifyAndDecodeTransaction()` 一步完成解码 + x5c 链校验 + bundleId/environment 比对。
  **该库不内置苹果根证书**，需从 apple.com/certificateauthority 下载三张 DER 根证书打进镜像，
  且苹果轮换根证书时要人工同步。
- **鉴权 JWT**：ES256，header `{alg, kid, typ}`，payload 五个 claim `iss/iat/exp/aud/bid`，
  `exp` 距 `iat` 不超过 60 分钟，`aud` 固定 `appstoreconnect-v1`。
  密钥在 ASC → Users and Access → Integrations → Keys → In-App Purchase，需 Account Holder 或 Admin。
- **生产与沙盒是不同 host**：`api.storekit.apple.com` / `api.storekit-sandbox.apple.com`，
  回调 URL 也分两个，必须分别配置。
- 客户端顺序：拿到 `Transaction.jwsRepresentation` → 发服务端 → 服务端验签并入账成功返 2xx →
  **客户端才调 `transaction.finish()`**。未确认前绝不 finish；重启后靠 `Transaction.updates`
  （启动后补发一次）与 `Transaction.unfinished`（可随时主动拉）双通道重放。

### 4.3 退款（最容易漏的一条）

- 苹果对 IAP 有单方面退款权，`REFUND` 通知是**退款已经成功之后**才发的，我们没有事先审批权。
- 收到 `CONSUMPTION_REQUEST` 后 **12 小时内**调 `PUT /inApps/v2/transactions/consumption/{transactionId}`
  回传消费数据供苹果裁定；**未取得用户明确同意（customerConsented）则不应调用、也不应响应**。
- **套利口必须堵**：现网 `getRefundableCents()` 直接等于 `topup` 池余额，账户注销时据此原路退现。
  若把 Apple 到账朴素地记成 `pool='topup'`，就会形成「用 Apple 付款买 Credits（我们只净收
  70%~84%），再向平台要求 100% 原路退现」的套利。必须给 IAP 到账的批次打上可区分的
  `sourceKind`，并让 `getRefundableCents` 把它排除在可退现之外。
- 苹果侧退款成功后必须有把对应 Credits 追回的路径（余额不足时记欠账，不能静默忽略）。
- **必须显式决定 IAP 单要不要叠会员充值赠送**：`settleOrderPaid` 现在对所有 `kind='recharge'`
  订单无差别按等级发 `reward`，且完全不看 `order.channel`。在 iOS 上叠加 10% 赠送会直接把
  本就微薄的净利打成负数。建议 IAP 单**不发**会员赠送，并同步决定要不要计入成长值。

---

## 5. 契约与界面（四端共用）

按 `contract-change` 规矩：先改 `contract/*.json` + `fixtures/`，跑 `gen.mjs`，再改各端。

- `strings.json` 新增 `balance.*` / `recharge.*` 键。**不要复用 `settings.usage`**——
  那是中转存储配额（`MediaUsage.usedBytes/quotaBytes`），与计费余额是两个概念，混用会造成语义冲突。
- `capabilities.json` 新增 `recharge` 能力，按端取值：ios=`iap`、miniprogram=`virtual`、
  android=`wxpay-app`、harmony=`false`。注意现有 capabilities 是**编译期静态开关、没有远程下发**，
  改值要走「改 JSON → gen → 各端重新发版」。
- `AccountUser` 已预留 `subscriptionType` 字段但四端都没接，可一并接上。
- **审核账号必须由服务端下发标志位**：`ReviewAccountGate` 是纯服务端机制，客户端零感知。
  若不下发标志，会出现审核员点充值调起真实支付的事故。iOS 侧因为 App Review 走沙盒购买
  不会真扣款，风险较低；小程序 iOS 端**没有沙箱**，必须在服务端把审核账号的充值入口关掉。

---

## 6. 顺带发现的两个存量缺陷（与充值无关，但会被本项目放大）

1. **`awdk_` Key 槽位泄漏（线上真实缺陷）**：`AwdkLoginService.exchangeAndBridge` 每次 Office 插件
   账户登录都经 `/api/auth/exchange-key` 换一把新 `awdk_`，用完即弃且**从不调用吊销**；
   而官网 `issueLoginKey` 与桌面端共用同一张 `api_keys` 表、同一条 `MAX_ACTIVE_KEYS=3`
   上限、同一套「满 3 个淘汰最旧未吊销 Key」策略。结果是每次插件登录都在共享槽位里留一枚僵尸 Key，
   累计满 3 个后会淘汰掉桌面端正在用的那把，表现为桌面端无预警掉线、提示「账户 Key 无效或已被撤销」。
   `awdk-login-enabled: true` 已是生产配置，这不是纸面风险。
2. **`account_binding.user_id` 缺唯一约束**：只有 `external_account_id` 有唯一约束。
   当前写入路径不可达重复，属防御性加固；但 `ddl-auto: update` 遇到已有重复数据会静默跳过约束创建，
   补约束前要先跑去重脚本。命中后表现是 HTTP 200 + `code:1` 通用错误（有全局兜底 handler），不是 500。

---

## 7. 需要开通的服务（用户动作清单）

按投入产出比排序。

### A. App Store 小企业计划（最高优先级，纯后台操作）

- **为什么**：国际版当前净收 70%（标准 30% 档），iOS 国际版充值每笔都在亏钱；
  加入后净收 85%，才勉强为正。大陆版实测已在优惠档（84.24%），可不动。
- **怎么做**：以 **Account Holder 身份**登录 App Store Connect（国际版是香港主体
  Team X9B97KVA84，Apple ID `hanzeweiasa@gmail.com`）→ Business → App Store Small Business Program →
  先接受最新 Paid Applications Agreement（Schedule 2）→ 申报所有关联开发者账号 → 提交申请。
- **注意**：条件是本人及关联账户上一年度与当年净收益均 ≤100 万美元。
  **大陆主体（京微资易 8WKHZVR2W8）与香港主体之间是否构成 Associated Developer Accounts
  （>50% 股权/控制权或同一终极决策权）需要你自己判断并如实申报**——这一点公开文档判不了。
- **生效时间**：批准所在苹果财务月月底后 15 天，不追溯。所以越早越好。

### B. Paid Applications Agreement + 银行与税务信息（iOS 内购的前提）

- 没有这份协议，内购商品在沙盒里都拉不出来，更不能上架。
- App Store Connect → Business → 接受 Paid Apps 协议 → 补齐联系人、银行账户、税务表单三部分，缺一不可。
- **两个主体各做一次**（香港主体与京微资易）。
- 资料齐全后审核通常数天；回款按月结，约 45 天。

### C. App Store Server 通知回调 URL（等服务端接口就绪后配）

- ASC REST API **不支持**读写这个 URL，只能网页操作：
  App Store Connect → 你的 App → App Information → App Store Server Notifications →
  分别填 Production URL 与 Sandbox URL，版本选 **Version 2**。
- 两个 App 各配一次。

### D. 微信小程序虚拟支付（做小程序充值的前提）

- 微信公众平台 → 左侧栏【虚拟支付】→ 开通。六步：①阅读并勾选协议 → ②提交企业营业执照、
  提现账户、支付管理员信息，开通**新的二级商户号**（不能复用官网现在用的商户号）→
  ③资料审核 1–7 个工作日 → ④账户验证（支付管理员配置为公司法人可跳过）→ ⑤扫码签约，
  签约后再审 1–2 个工作日 → ⑥进入商户管理后台配道具。
- **全程约 2–9 个工作日**，两段审核是串行的。
- 提现账户很可能要求对公（官方页面只写「提现账户」，社区反馈个体户目前只支持对公），以实际表单为准。
- 开通后、联调 iOS 前还要在【虚拟支付 → 基础配置】里配好**小程序简称**（Apple 支付要展示 display name）。
- 结算 T+3；iOS 端的钱由苹果结算给腾讯（自然月结束后 45–60 天）再转给我们。

### E. 微信支付 APP 支付（做安卓充值的前提，可与 D 并行）

- ①微信开放平台注册开发者账号并完成资质认证（客服页写认证费 300 元/次）→
  ②创建「移动应用」，Android 登记包名 `com.aiworkdeck.mobile.cn` + 应用签名，
  iOS 登记 Bundle ID + Universal Links → 开放平台审核 1–7 个工作日 →
  ③微信支付商户平台【产品中心 → APP 支付 → 申请开通】，提交 APPID、应用页面截图、应用商店下载链接 →
  审核 7 个工作日内。
- **可以现在就申请**：材料里的「应用商店下载链接」用已上架的 iOS App Store 链接即可满足，
  不必等安卓包先上架。这条不用和安卓上架串行。

### F. 支付宝 APP 支付（可选，安卓第二通道）

- open.alipay.com（企业实名认证账号）→ 创建「移动应用」，报包名+签名 / Bundle ID →
  添加「APP 支付」能力 → 生成 RSA 密钥对上传应用公钥 → 提交上线审核（约 1 个工作日）→
  应用「已上线」后对 APP 支付能力单独签约 → 签约生效才可用于生产。
- **不要求 App 已在外部应用商店上架**，比微信宽松。

### G. 提审前必须实测的两家安卓商店（不是开通，是验证）

- **应用宝**：其审核规范有「涉及支付功能需接入腾讯支付，第三方支付可能被拒」的表述且不限品类。
- **小米**：留有一条旧规范要求应用存在付费项需联系商务。
- 两家都要用带充值功能的测试包实际提审验证，不能凭调研定案。

---

## 8. 分期建议

| 期 | 内容 | 前置 | 净利/100 元 |
|---|---|---|---|
| 一 | 服务端账户映射 + 余额读取（#425）；四端只展示余额、不放充值入口（#429） | 无 | — |
| 二 | 小程序虚拟支付充值（#427） | D | +19（安卓）/ +8（iOS） |
| 三 | iOS 内购（#426） | A、B、C | +5（国际，需先做 A）/ +4（大陆） |
| 四 | 安卓 App 微信支付（#428） | E，且安卓端本体先上架 | +19 |
| 五 | 鸿蒙 | 客户端本体 | — |

把小程序排在 iOS 前面，是因为它抽成最低、覆盖大陆主力用户、且不受苹果条款约束；
iOS 排第三是因为它依赖三项用户侧开通动作，其中小企业计划的生效还有月底 +15 天的延迟。

**第一期是无条件可做的**：只展示余额不放充值入口，四端都合规（iOS 落在「免费 App 零购买」现状，
小程序不触发虚拟支付强制条款），而且它是后面每一期的共同地基。
