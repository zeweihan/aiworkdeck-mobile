import StoreKit
import SwiftUI

/// 充值页 —— App Store 内购（dev-board#426）。
///
/// 五步流程与判定条件的唯一来源是 `docs/specs/2026-09-13-ios-iap-and-four-end-alignment-plan.md` §1：
/// 幂等键先落盘 → 建单拿 appAccountToken → `Product.purchase` → confirm 回 paid → **这时才 finish**。
///
/// 档位只能来自契约（`contract/products.json` 的 appstore 段 → `ContractProducts.appstore`），
/// **价格一律用 StoreKit 的 `displayPrice`**：苹果按买家 storefront 定价与本地化，页面里手抄
/// 一份「¥50」在别的地区就是错的，而 amountCents 只是站点币种面值，用于与官网权威表对账。
struct RechargeView: View {
    var onClose: () -> Void

    /// 契约档位 ∩ StoreKit 商品。
    private struct Tier: Identifiable {
        let productId: String
        let amountCents: Int
        let product: Product
        var id: String { productId }
    }

    @State private var tiers: [Tier] = []
    @State private var loading = true
    /// 商品取不回来（离线、沙盒未登录、Paid Applications 协议没签）：页面只剩一句说明，
    /// 不画空档位列表，也不假装还在加载。
    @State private var storeUnavailable = false
    @State private var busy = false
    @State private var hint = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: T.Sp.s3) {
                    Eyebrow(text: tr("recharge.pick"))
                        .padding(.top, T.Sp.s6)

                    if loading {
                        Text(tr("recharge.ios.priceLoading"))
                            .font(T.F.small())
                            .foregroundStyle(T.L.fgFaint)
                    } else if storeUnavailable || tiers.isEmpty {
                        Text(tr("recharge.ios.storeUnavailable"))
                            .font(T.F.small())
                            .foregroundStyle(T.L.fgFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(tiers) { tier in
                            tierRow(tier)
                        }
                    }

                    if !hint.isEmpty {
                        Text(hint)
                            .font(T.F.nano())
                            .foregroundStyle(T.L.fgFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, T.Sp.s2)
                    }

                    Hairline().padding(.vertical, T.Sp.s4)

                    // 钱已经付了但没入账的交易（进程被杀、confirm 失败）留在 Transaction.unfinished 里。
                    // 启动时自动重放一次，这个按钮是用户手上的那根绳子。
                    Button(tr("recharge.ios.restore")) { Task { await restore() } }
                        .font(T.F.small())
                        .foregroundStyle(T.L.accent)
                        .frame(minHeight: T.touchMin, alignment: .leading)
                        .disabled(busy)
                }
                .padding(.horizontal, T.Sp.gutter)
                .padding(.bottom, T.Sp.s16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(T.L.bg)
            .navigationTitle(tr("recharge.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("common.close"), action: onClose) }
            }
            .task { await loadTiers() }
        }
    }

    private func tierRow(_ tier: Tier) -> some View {
        Button {
            Task { await buy(tier) }
        } label: {
            HStack {
                // 展示价一律来自 StoreKit：本地化、含税口径都由苹果给，我们不复算
                Text(tr("recharge.tier", ["amount": tier.product.displayPrice]))
                    .font(T.F.body())
                    .foregroundStyle(T.L.fg)
                Spacer()
                Text(tr("recharge.entry"))
                    .font(T.F.small())
                    .foregroundStyle(T.L.accent)
            }
            .frame(minHeight: T.touchMin)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: 行为

    private func loadTiers() async {
        let wanted = ContractProducts.appstore
        guard let products = try? await Product.products(for: wanted.map(\.productId)) else {
            loading = false
            storeUnavailable = true
            return
        }
        let byId = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        let usable = RechargeTiers.intersect(contract: wanted, storeProductIds: products.map(\.id))
        tiers = usable.compactMap { p in
            byId[p.productId].map { Tier(productId: p.productId, amountCents: p.amountCents, product: $0) }
        }
        loading = false
        storeUnavailable = tiers.isEmpty
    }

    private func buy(_ tier: Tier) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await purchase(tier, retryOnKeyConflict: true)
        } catch let e as API.BillingError {
            // 服务端 message 经 LangText 已是可读话术，原样展示；不按措辞分支
            hint = e.message
        } catch {
            hint = tr("recharge.failed")
        }
    }

    private func purchase(_ tier: Tier, retryOnKeyConflict: Bool) async throws {
        let key = IAP.takeIdempotencyKey(productId: tier.productId)
        let order: API.RechargeOrder
        do {
            order = try await API.shared.billingRecharge(channel: "appstore", productId: tier.productId,
                                                         amountCents: tier.amountCents, idempotencyKey: key)
        } catch let e as API.BillingError {
            // 这把键上已经有一笔付过的单（ALREADY_PAID）、或同一把键换了金额（IDEMPOTENCY_CONFLICT）：
            // 换新键重来一次，**只重来一次**，避免打转
            if retryOnKeyConflict, e.kind == .alreadyPaid || e.kind == .idempotencyConflict {
                IAP.clearIdempotencyKey()
                return try await purchase(tier, retryOnKeyConflict: false)
            }
            throw e
        }
        // appAccountToken 是这笔单与 StoreKit 交易之间唯一的挂钩，拿不到就别扣钱
        guard order.present == "native",
              let token = order.appAccountToken.flatMap({ UUID(uuidString: $0) }) else {
            throw API.BillingError(message: tr("recharge.failed"), kind: nil, outTradeNo: nil)
        }

        hint = tr("recharge.ios.pending")
        let result = try await tier.product.purchase(options: [.appAccountToken(token)])
        switch result {
        case .success(let verification):
            guard case .verified(let tx) = verification else {
                // StoreKit 自己都不认这份签名，送去服务端也只会被 REJECTED
                hint = tr("recharge.failed")
                return
            }
            if await IAP.confirm(tx, jws: verification.jwsRepresentation, outTradeNo: order.outTradeNo) {
                IAP.clearIdempotencyKey()
                hint = tr("recharge.success")
            } else {
                // 没确认成功就**没有 finish**：交易留在 Transaction.unfinished 里等下次重放
                hint = tr("recharge.pendingLong")
            }
        case .userCancelled:
            // 取消不清幂等键：同一档再点一次要复用同一把键，不能变成两笔单
            hint = tr("recharge.cancelled")
        case .pending:
            // Ask to Buy 等家长批准：批准后 Transaction.updates 会补发，那条路自己会去 confirm
            hint = tr("recharge.pendingLong")
        @unknown default:
            hint = tr("recharge.failed")
        }
    }

    private func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        hint = tr("recharge.ios.pending")
        let landed = await IAP.replayUnfinished()
        hint = landed > 0 ? tr("recharge.success") : tr("recharge.ios.restoreNone")
    }
}
