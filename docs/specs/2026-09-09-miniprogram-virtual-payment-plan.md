# 小程序虚拟支付充值（第二期）实施方案

日期 2026-09-09。看板卡 dev-board#427（小程序虚拟支付）+ dev-board#434（注销传导，本期必须一起落地）。
设计源仍是 `2026-09-04-mobile-recharge-design.md`（§2.2 / §3 / §5 / 第二期开工清单），本文只写第二期的实施决定，
不重复那里的论证。

## 0. 已就绪的外部条件（用户侧已完成）

- 公众平台【虚拟支付】已签约，基本配置：appid `wx67b9a7d0449be0b4`，OfferID `1450637533`，平台路径开、苹果 IAP 已开通。
- 道具三档已发布到现网（微信单道具上限 100 元，所以没有 300 档）：

  | productId | 名称 | 价格（分） |
  |---|---|---|
  | `credits_cny_10` | 代币10元 | 1000 |
  | `credits_cny_50` | 代币50元 | 5000 |
  | `credits_cny_100` | 代币100元 | 10000 |

- 两把 AppKey 已在北京 ECS 官网 `.env.local`：`WXVP_APP_KEY`（现网）、`WXVP_APP_KEY_SANDBOX`（沙箱）、`WXVP_OFFER_ID`。
- 小程序「消息推送」（开发管理 → 开发设置 → 消息推送）**尚未配置**，等官网接收口上线后由用户填 URL + Token。

## 1. 端到端流程

```
小程序 pages/recharge          Java addin.aiworkdeck.com            官网 aiworkdeck.com
─────────────────────          ─────────────────────────            ───────────────────
选档位 → wx.login() 取 code
POST /api/mobile/billing/recharge
  {channel:"wxvp", productId,
   amountCents, idempotencyKey,
   wxCode}                 ──▶ 校验 → 解析 accountId(create=true)
                               POST /api/internal/account
                               {action:"create-recharge",
                                accountId, channel:"wxvp",
                                productId, amountCents,
                                idempotencyKey, wxCode}      ──▶ jscode2session(wxCode) → openid + session_key
                                                                  校验 productId↔amountCents（官网是价格权威）
                                                                  建单 orders(channel="wxvp", providerRef=openid)
                                                                  signData = JSON 串（offerId, buyQuantity:1, env,
                                                                    currencyType:"CNY", productId, goodsPrice,
                                                                    outTradeNo, attach}
                                                                  paySig = hex(hmac_sha256(appKey, "requestVirtualPayment&"+signData))
                                                                  signature = hex(hmac_sha256(session_key, signData))
                           ◀── 透传 {present:"virtual", outTradeNo,  ◀── {present:"virtual", outTradeNo, amountCents,
                               amountCents, signData, paySig,          signData, paySig, signature}
                               signature}
wx.requestVirtualPayment({
  signData, paySig, signature,
  mode:"short_series_goods"})
支付成功 → 轮询
GET /recharge/status?outTradeNo ──▶ 透传                        ──▶ action:"query"：本地 pending 则调 /xpay/query_order
                                                                  已支付 → settleFromChannel 入账
                                                              微信推送 xpay_goods_deliver_notify
                                                              ──▶ POST /api/wx-mini/push：验签 → query_order 复核 → 入账
                                                                  → 回 {ErrCode:0}
```

沙箱/现网由官网 env `WXVP_ENV`（`sandbox` | `production`，缺省 `production`）决定，`env` 字段与所用 AppKey 随之切换；
不按请求切换，联调期整站沙箱、验收后切现网。iOS 微信没有沙箱，只能现网小额真付。

## 2. 契约（移动仓 `contract/`，先改这里再 gen）

- `schema/billing.schema.json` 与 `api/mobile-v1.yaml`：`present` 枚举加 `virtual`；`RechargeOrder` 加可选
  `signData` / `paySig` / `signature`（present=virtual 时三者必有值，其余 present 时缺席 → 解成 null，与 codeUrl 三兄弟同规则）。
- `POST /api/mobile/billing/recharge` 请求体加可选 `channel`（枚举暂只有 `wxvp`，缺省走站点默认通道，即第一期行为）、
  `productId`、`wxCode`；`channel=wxvp` 时三者必填，缺失 code 1 无 kind（通用 handler）。
- `fixtures/billing.json`：`recharge` 加 virtual 用例（signData 三键都在，codeUrl 三兄弟缺席 → null）；
  `envelope` 加 `REJECTED：档位与金额不符`（措辞见 §4）。
- 新文件 `contract/products.json`：`{"wxvp":[{"productId":"credits_cny_10","amountCents":1000},…]}`，gen 出各端常量；
  小程序档位列表只从这里来。官网另有自己的权威价格表，不一致时官网回 400 `product_mismatch` → Java 译成 REJECTED。
- `strings.json` 新键（zh-Hans / en 都给）：`recharge.title`（充值 / Top up）、`recharge.pick`（选择充值金额 / Choose an amount）、
  `recharge.pay`（微信支付 / Pay with WeChat）、`recharge.paying`（正在确认到账… / Confirming payment…）、
  `recharge.success`（充值成功，余额已更新 / Top-up successful）、`recharge.cancelled`（已取消支付 / Payment cancelled）、
  `recharge.failed`（支付未完成，请稍后再试 / Payment did not complete. Try again later.）、
  `recharge.pendingLong`（支付已提交，到账稍有延迟，可稍后下拉刷新余额 / Payment submitted; balance will update shortly）、
  `recharge.tier`（{amount} / {amount}）。
- `check.mjs` 的 `FIXTURE_CONSUMERS`：本期把 `miniprogram` 填进 recharge / status 两段（小程序写走生产解码路径的夹具适配测试）。
  iOS / 安卓 / 鸿蒙本期不做充值界面，只要求 gen 后仍编译、既有测试仍绿。

## 3. 官网（仓 aiworkdeckweb，`lib/payments/` 加 `wxvp-adapter.ts`）

- `PaymentChannelId` 扩为 `'wxpay' | 'stripe' | 'wxvp'`；`CreateChargeResult` 加
  `{ channel:'wxvp'; present:'virtual'; signData; paySig; signature; providerRef(openid) }`。
  `createCharge` 输入加可选 `productId` / `wxCode`（wxvp 必填）。
- `handleCreateRecharge`：`body.channel === 'wxvp'` 时用 wxvp 适配器而不是 `getPaymentAdapter()`；
  校验 `productId` 在权威表内且 `amountCents` 相等（否则 400 `product_mismatch`）；幂等键复用既有逻辑；
  `orders.channel='wxvp'`，`providerRef=openid`。
- `jscode2session`：`lib/wx-mini.ts` 加 `wxCode2Session(code)`（GET `/sns/jscode2session`，用 `WX_MINI_APP_SECRET`），
  session_key 只在内存里用于签名，**不落库、不打日志**。
- 微信服务端接口签名：`pay_sig = hex(hmac_sha256(appKey, uri + '&' + postBody))`，uri 形如 `/xpay/query_order`；
  access_token 复用 `lib/wx-mini.ts` 的 stable_token。`queryCharge` 调 `/xpay/query_order`（openid 从 order.providerRef 取），
  官方文档的字段名以 `curl https://developers.weixin.qq.com/miniprogram/dev/platform-capabilities/business-capabilities/virtual-payment.html`
  抓下来的原文为准，PR 描述里贴引用的字段清单。
- 新路由 `app/api/wx-mini/push/route.ts`（小程序消息推送接收口）：
  - GET：`signature` = sha1(sort(token, timestamp, nonce)) 验签通过则原样回 `echostr`（公众平台保存配置时的校验）。
  - POST：先验 `signature`，再解析 JSON（配置选「JSON + 明文模式」；若 `encrypt_type=aes` 直接 400，不做安全模式）。
    `Event === 'xpay_goods_deliver_notify'` → 取 `OutTradeNo`，**不直接信推送里的金额**，调 `/xpay/query_order` 复核后
    `settleFromChannel`；重复推送幂等（`alreadyPaid` 也回成功）。其它事件记日志回成功。响应 `{ErrCode:0, ErrMsg:"", ...}`
    按文档要求的形状回；处理失败回 `ErrCode` 非 0 让微信重试（最多 15 次）。
  - Token 从 env `WXVP_PUSH_TOKEN` 读，缺省时整个路由回 404。
- 新 action `delete-account`（dev-board#434）：`{action:'delete-account', accountId}` →
  调 `lib/account-deletion.ts` 的 `deleteAccount(userId)`：Done → 200 `{deleted:true}`；
  Blocked → 200 `{deleted:false, blocker:<DeletionBlockerCode>, message}`；KeyDisableFailed → 502 `{error:'key_disable_failed'}`；
  查无账户或已是墓碑 → 404 `account_not_found`（Java 视为已删）。
- env 新增：`WXVP_ENV`、`WXVP_PUSH_TOKEN`（`WXVP_APP_KEY*` / `WXVP_OFFER_ID` 已在服务器）。
  `.env.example`（若有）与 `docs/` 里的 env 清单同步。
- 验证：`npm run typecheck && npm run lint && npm run build`；签名函数与推送验签写可独立跑的验证脚本
  （沿用 `scripts/verify-*.mts` 风格），用文档示例向量对拍。

## 4. Java 云后端（仓 aiworkdeck / checkba_cloud，`backend/`）

- `RechargeRequest` 加 `channel` / `productId` / `wxCode`；`MobileBillingService.createRecharge` 校验：
  `channel` 为空 → 第一期行为；`channel="wxvp"` → `productId` 必须匹配 `^[a-z0-9_]{1,64}$`、`wxCode` 非空、
  `amountCents` > 0；其它 channel 值 → IllegalArgument（code 1 无 kind）。
- `MobileBillingClient.createRecharge` 签名扩展（channel/productId/wxCode 透传）；`RechargeOrder` 记录加
  `signData` / `paySig` / `signature`；控制器 `putIfPresent` 三个新键。
- `HttpMobileBillingClient.parse`：400 `product_mismatch` → REJECTED，message
  `LangText.of("充值档位与金额不符，请更新小程序后重试", "Top-up tier and amount do not match; please update the mini program and try again")`。
- 注销传导（dev-board#434）：`AccountDeletionService.deleteAccount` 在删本地表**之前**，若存在 `account_binding`，
  调 `MobileBillingClient.deleteAccount(accountId)`：
  - 官网 `deleted:true` 或 404 → 继续删本地；
  - `deleted:false` → 抛可读业务错误（code 1，message 用官网给的 message，英文部署走 LangText），本地**不删**；
  - 官网不可达 / 5xx / 未配 base-url·secret → 抛 UNAVAILABLE 类可读错误，本地不删（宁可让用户稍后再试，
    也不能留下官网侧孤儿账户）。**例外**：本机未配 `mobile.billing.*`（DISABLED）且没有 binding 时照常删。
- `mobile-v1.yaml` 同步 §2 的形状；`MobileApiContractTest.billingEndpointsMatchSpec` 覆盖 present=virtual 与新请求字段；
  `MobileBillingServiceTest` / `HttpMobileBillingClientTest` 补 wxvp 与 delete-account 分支；
  `AccountDeletionService` 补三分支测试（deleted / blocked / unavailable）。
- 验证：backend 既有测试命令（pom/gradle 按仓内约定）跑上述测试类全部绿，PR 里贴命令与输出。

## 5. 小程序（本仓 `miniprogram/`）

- `pages/project` 余额行右侧加「充值」入口（`recharge.entry` 已有键），`CAPS.recharge === 'virtual'` 且余额行可见时才渲染；
  审核账号 / DISABLED / NOT_CONNECTED 三态余额行本就不渲染，入口随之消失。
- 新页 `pages/recharge/recharge`：档位列表来自 gen 出的 products 常量；选中后：
  1. `idempotencyKey` = `uuid()` 生成后**先写 storage** 再发请求（App 被杀可复用）；
  2. `wx.login()` 取 code；
  3. `billingRecharge({channel:'wxvp', productId, amountCents, idempotencyKey, wxCode})`；
  4. `wx.requestVirtualPayment({signData, paySig, signature, mode:'short_series_goods'})`；
     fail 且 `errMsg` 含 `cancel` → `recharge.cancelled`；其它 fail → `recharge.failed`；
  5. success → 轮询 `billingRechargeStatus(outTradeNo)`，间隔 1.5 s、最多 8 次；`paid` → 清 storage 里的幂等键、
     toast `recharge.success`、返回上一页触发余额刷新；超时未 paid → `recharge.pendingLong`（不清幂等键）。
  6. Envelope `kind=ALREADY_PAID` → 直接拿 outTradeNo 走第 5 步；`IDEMPOTENCY_CONFLICT` → 丢掉旧幂等键重来一次。
- `utils/api.ts` 加 `billingRecharge` / `billingRechargeStatus`（裸对象，`{bare:true}`，同 `billingBalance`）。
- 所有文案走 `t()`，`check.mjs` 必须绿。夹具适配测试：`tests/contract.test.ts`（或新文件）用生产解码路径消费
  `fixtures/billing.json` 的 `recharge` / `status` 两段。
- 版本：`0.33.0`，备注「小程序虚拟支付充值（dev-board#427）」。上传与提审由主会话在三仓合并、服务端部署、联调通过后做。

## 6. 上线顺序（主会话执行）

1. 官网 PR 合并部署 → 用户在公众平台配消息推送（URL `https://aiworkdeck.com/api/wx-mini/push`、Token 与服务器 `WXVP_PUSH_TOKEN` 同值、JSON、明文）。
2. Java PR 合并部署；服务器 env 配 `MOBILE_BILLING_BASE_URL` / `MOBILE_BILLING_SECRET`（官网侧 `AWD_MOBILE_BILLING_SECRET` 同值）；
   #434 落地后才允许 `MOBILE_BILLING_RECHARGE_ENABLED=true`。
3. 移动仓 PR 合并 → `pull-api.mjs` 重钉 PINNED → 上传 0.33.0 体验版 → 官网 `WXVP_ENV=sandbox` 用体验版跑沙箱 →
   切 `production` 用 1 元档真付一笔并退款/留存 → 提审。
