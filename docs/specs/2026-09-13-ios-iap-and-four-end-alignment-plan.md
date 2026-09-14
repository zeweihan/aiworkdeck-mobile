# iOS 内购充值 + 四端充值对齐 实施方案

日期 2026-09-13。看板：dev-board#426（iOS 内购）、#427（小程序虚拟支付，复测中）、#428（安卓）。
设计源：`2026-09-04-mobile-recharge-design.md` §4（IAP 详细设计，本文不重复）、§5；小程序侧 `2026-09-09-miniprogram-virtual-payment-plan.md`。
制度：`docs/MOBILE_DEV_DISCIPLINE.md`。

## 0. 四端矩阵

| 端 | 本次 | 说明 |
|---|---|---|
| iOS | **做**：StoreKit 2 内购充值页 + 服务端确认 + 提审 1.1.0 | ASC 大陆 App 6803309103 已有消耗型 `credits.cny.50/100/300`（MISSING_METADATA，等截图） |
| 小程序 | 修：道具价格单位——微信后台与 start_upload_goods 的 price 是**元**，signData 的 goodsPrice 是**分**；三档经接口改为 10/50/100 元后真机可付（2026-09-14 实测） | 其余不动 |
| 安卓 | **对齐入口**：设置页余额行 + 「充值」行，点开说明「安卓 App 内充值开通中，请先在微信小程序充值」 | 微信开放平台 APP 支付未开通（用户动作，手册 §D），开通后再做 #428 |
| 鸿蒙 | 同安卓的对齐入口 | 无支付通道，`capabilities.recharge=false` 不变 |

## 1. iOS 端到端流程

```
iOS SettingsView 余额行「充值」→ RechargeView
  1. 档位来自契约 products.json 的 appstore 段（credits.cny.50/100/300），用 StoreKit 2 Product.products(for:) 取本地化价格展示
  2. 点购买：idempotencyKey 落盘 → POST /api/mobile/billing/recharge {channel:"appstore", productId, amountCents, idempotencyKey}
     → Java 透传官网 create-recharge(channel appstore) → 官网建单 orders(channel=appstore, providerRef=UUID appAccountToken)
     → 回 {present:"native", outTradeNo, amountCents, appAccountToken}
  3. product.purchase(options:[.appAccountToken(UUID)]) → .success(.verified(tx))
  4. POST /api/mobile/billing/recharge/confirm {outTradeNo, signedTransaction: tx.jwsRepresentation}
     → Java 透传官网 confirm-appstore → 官网 SignedDataVerifier 验签（bundleId com.aiworkdeck.mobile.cn、appAppleId 6803309103、
       environment 按 env）→ 校 appAccountToken==providerRef、productId==order、transactionId 未用过 → settleFromChannel
     → 回 RechargeStatus {status:"paid", paid:true, amountCents}
  5. 收到 paid 后 tx.finish()；未确认前绝不 finish。
  6. 启动时 Transaction.updates + Transaction.unfinished 重放：对每笔未 finish 的交易，用 appAccountToken 找不到本地 outTradeNo 时
     调 confirm 时只带 signedTransaction（outTradeNo 可省），官网用 appAccountToken 反查 providerRef。
```

审核账号：服务端 REVIEW_ACCOUNT 时余额行与充值入口整体不渲染（既有规则），App Review 用沙盒账号真实购买不扣款。

## 2. 契约（移动仓）

- `present` 枚举加 `native`；`RechargeOrder` 加可选 `appAccountToken`（present=native 必有；其它 present 缺席→null）。
- `POST /recharge` 请求体 `channel` 枚举加 `appstore`（此时 productId 必填、wxCode 不填）。
- 新端点 `POST /api/mobile/billing/recharge/confirm`，请求 `{outTradeNo?, signedTransaction}`，响应 `RechargeStatus | Envelope`；
  Envelope kind：REJECTED（验签失败 / 订单不符 / 交易已用过）、NOT_FOUND（查无单）、UNAVAILABLE。
- `products.json` 加 `appstore: [{productId:"credits.cny.50", amountCents:5000}, …100, …300]`。
- `strings.json` 新键：`recharge.ios.priceLoading`（正在获取价格… / Loading prices…）、`recharge.ios.storeUnavailable`
  （暂时无法连接 App Store，请稍后再试 / App Store unavailable. Try again later.）、`recharge.ios.pending`
  （购买已提交，正在确认到账… / Purchase submitted, confirming…）、`recharge.ios.restore`（恢复未完成的购买 / Restore pending purchases）、
  `recharge.external.title`（App 内充值开通中 / In-app top-up coming soon）、`recharge.external.body`
  （请先在微信小程序「AI WorkDeck」的「我的 → 充值」里充值，余额四端通用 / Top up in the WeChat mini program for now; balance is shared across devices）。
- fixtures：recharge 加 native 用例；status 不变；envelope 加 REJECTED「交易验证失败」用例。
- `check.mjs` FIXTURE_CONSUMERS：ios 填进 recharge / status。

## 3. 官网（aiworkdeckweb）

按设计 §4.2 / §4.3：`lib/payments/appstore-adapter.ts` + `appstore-catalog.ts`（productId→面值分，站点币种 CNY）；
依赖 `@apple/app-store-server-library`；三张苹果根证书 DER 进仓 `lib/payments/apple-roots/`（来源 apple.com/certificateauthority，PR 里写下载 URL 与 sha256）。
- 内部口 action：`create-recharge` 支持 `channel:'appstore'`（productId 必填，amountCents 与目录表一致否则 400 product_mismatch；
  回 `{present:'native', outTradeNo, amountCents, appAccountToken}`）；新 action `confirm-appstore`
  `{accountId, outTradeNo?, signedTransaction}` → 验签 → 校订单 → settle → 回 query 形状；失败 400 `transaction_invalid` /
  409 `transaction_reused` / 404 `order_not_found`。
- Server Notifications V2：`app/api/appstore/notifications/route.ts`，验 signedPayload；`REFUND` → 按 transactionId 找单、
  记 `refundedAt`、追回 Credits（余额不足记欠账，用现有 wallet 能力，没有就记日志 + 返回 200 并在报告里标未实现）；
  其它类型记日志回 200。沙盒与生产各一个 URL（同一路由按 payload 的 environment 分流）。
- IAP 单**不发**会员充值赠送、`sourceKind='appstore'` 且不计入可退现（§4.3）。
- env：`APPSTORE_BUNDLE_ID=com.aiworkdeck.mobile.cn`、`APPSTORE_APP_APPLE_ID=6803309103`、`APPSTORE_ENV`（sandbox|production，
  验签允许两者：生产环境下沙盒交易只在审核账号或明确 allowlist 时接受——先实现为 env 决定，report 里标注）。
- 验证：`scripts/verify-appstore.mts`，用库自带的测试 JWS 或自签测试链跑验签分支；typecheck/lint/build 绿。

## 4. Java

- `RechargeRequest.channel` 允许 `appstore`（productId 必填，wxCode 不要）；透传；`RechargeOrder` 加 `appAccountToken`。
- 新端点 `POST /api/mobile/billing/recharge/confirm`（X-Session-Id）→ `MobileBillingClient.confirmAppstore(accountId, outTradeNo, signedTransaction)`
  → 官网 `confirm-appstore`；映射：400 transaction_invalid → REJECTED、409 transaction_reused → REJECTED（message「该交易已使用」）、404 → NOT_FOUND。
  成功回 RechargeStatus 形状；paid 时清余额缓存。
- yaml 同步；`MobileApiContractTest` 加 confirm 端点用例；`HttpMobileBillingClientTest` / `MobileBillingServiceTest` 补分支。

## 5. iOS App

- `ios/Sources/Services/Backend.swift` 加 `billingRecharge(channel:productId:amountCents:idempotencyKey:)`、`billingRechargeConfirm(outTradeNo:signedTransaction:)`、
  `billingRechargeStatus`。
- `Features/Settings/RechargeView.swift`：档位 = 契约 products.appstore ∩ StoreKit 返回的 Product（缺的档位不显示，不能 crash）；
  购买流程按 §1；`StoreKitObserver`（App 启动挂 `Transaction.updates`）；错误态用契约文案；审核账号不渲染入口。
- Xcode：`Workdeck.storekit` 配置文件（三档，价格与 ASC 一致）用于模拟器测试；scheme 的 StoreKit Configuration 指向它。
- 版本 `MARKETING_VERSION` → 1.1.0。
- 单测：Backend 解码 native 夹具、confirm 请求体形状；UI 用模拟器截图（设置页 → 充值页 → 购买弹层 → 成功态）。

## 6. 安卓 / 鸿蒙对齐

- 设置页余额行下加「充值」行；点开 Dialog：`recharge.external.title` / `recharge.external.body`。
- `capabilities.json`：android `recharge` 由 `wxpay-app` 改为 `external`（尚未接通支付，入口只做引导）；harmony 由 `false` 改为 `external`。
  等 #428 真接通再改回 `wxpay-app`。
- 各自单测绿；模拟器截图（安卓 / 鸿蒙能起就截，起不了如实说）。

## 7. 上线顺序（主会话）

1. 官网 PR → 合并自动部署；服务器 env 加 APPSTORE_*；ASC 配 Server Notifications URL（沙盒 + 生产）。
2. Java PR → 合并 → 从 master 打包部署。
3. 移动仓 PR → 合并 → pull-api 重钉 → `[appstore]` 推 TestFlight → 用模拟器/TestFlight 截 IAP 审核截图 → ASC：IAP 元数据（截图 + 审核备注）、
   建 1.1.0 版本、附 3 个 IAP、提审。
4. 安卓/鸿蒙随同一 PR 出包到 dist/。

## 8. 等用户（提审前必须）

- ASC：Paid Applications 协议 + 银行税务（手册 §B）——没签内购商品无法上线，沙盒也取不到商品。
- ASC：In-App Purchase 密钥（Users and Access → Integrations → In-App Purchase）——退款/消费信息接口用；p8 放 `~/.aiworkdeck/`，不入库。
- 微信开放平台 APP 支付（手册 §D）——安卓真充值的前提。
