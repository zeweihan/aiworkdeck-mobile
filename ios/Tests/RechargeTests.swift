import XCTest
@testable import Workdeck

/// 内购充值里不由夹具驱动的三件事（dev-board#426）：请求体形状、档位求交、幂等键落盘。
final class RechargeTests: XCTestCase {
    /// 建单请求体。**channel=appstore 时不能带 wxCode**——那是小程序虚拟支付换 openid +
    /// session_key 用的，内购这条路上根本没有微信；多带一个键会被服务端按未知字段处理。
    func testRechargeBodyCarriesChannelProductAndKeyButNoWxCode() {
        let body = API.rechargeBody(channel: "appstore", productId: "credits.cny.50",
                                    amountCents: 5000, idempotencyKey: "K-1")
        XCTAssertEqual(Set(body.keys), ["channel", "productId", "amountCents", "idempotencyKey"])
        XCTAssertEqual(body["channel"] as? String, "appstore")
        XCTAssertEqual(body["productId"] as? String, "credits.cny.50")
        XCTAssertEqual(body["amountCents"] as? Int, 5000)
        XCTAssertEqual(body["idempotencyKey"] as? String, "K-1")
        XCTAssertNil(body["wxCode"])
        // 真发得出去才算数：JSONSerialization 认这份字典
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    /// 确认到账的请求体。签名串必带；outTradeNo 可省——App 被杀后重放未完成交易时本地没有单号，
    /// 官网用 JWS 里的 appAccountToken 反查 providerRef。**省掉时这个键不能出现**，
    /// 不能退化成空串（服务端按「有这个键」去找单，空串必然查无此单）。
    func testConfirmBodyOmitsOutTradeNoWhenAbsent() {
        let withOrder = API.confirmBody(outTradeNo: "awd20260913000127", signedTransaction: "JWS")
        XCTAssertEqual(Set(withOrder.keys), ["outTradeNo", "signedTransaction"])
        XCTAssertEqual(withOrder["outTradeNo"] as? String, "awd20260913000127")
        XCTAssertEqual(withOrder["signedTransaction"] as? String, "JWS")

        XCTAssertEqual(Set(API.confirmBody(outTradeNo: nil, signedTransaction: "JWS").keys),
                       ["signedTransaction"])
        // 空串与缺席同义：一样不出这个键
        XCTAssertEqual(Set(API.confirmBody(outTradeNo: "", signedTransaction: "JWS").keys),
                       ["signedTransaction"])
    }

    /// 档位 = 契约 ∩ StoreKit。StoreKit 没返回的档位直接不显示（商品还没审核通过、该地区没上架、
    /// id 打错），显示一个买不了的按钮比少一个档位糟得多；顺序跟契约走，不跟 StoreKit 的返回顺序走。
    func testTiersAreContractIntersectStoreKeepingContractOrder() {
        let contract = ContractProducts.appstore
        XCTAssertEqual(contract.map(\.productId), ["credits.cny.50", "credits.cny.100", "credits.cny.300"])

        // StoreKit 少一档、顺序还反着：结果按契约顺序，缺的那档不出现
        let partial = RechargeTiers.intersect(contract: contract,
                                              storeProductIds: ["credits.cny.300", "credits.cny.50"])
        XCTAssertEqual(partial.map(\.productId), ["credits.cny.50", "credits.cny.300"])

        // 一个都取不回来：空列表，不能崩（界面据此显示 recharge.ios.storeUnavailable）
        XCTAssertTrue(RechargeTiers.intersect(contract: contract, storeProductIds: []).isEmpty)

        // StoreKit 多出契约里没有的 id：不显示，档位来源永远是契约
        XCTAssertEqual(RechargeTiers.intersect(contract: contract,
                                               storeProductIds: ["credits.cny.50", "credits.cny.999"])
                        .map(\.productId), ["credits.cny.50"])

        // 面值与契约一致，端上不另抄一份价格
        XCTAssertEqual(contract.map(\.amountCents), [5000, 10000, 30000])
    }

    /// 幂等键**先落盘再发请求**：同一档位重进页面复用同一把键（服务端 UNIQUE 兜底，不会变成
    /// 两笔单），换档位换新键，清掉之后再取也是新键。
    func testIdempotencyKeyIsStickyPerProductUntilCleared() {
        IAP.clearIdempotencyKey()
        let first = IAP.takeIdempotencyKey(productId: "credits.cny.50")
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(IAP.takeIdempotencyKey(productId: "credits.cny.50"), first)

        let other = IAP.takeIdempotencyKey(productId: "credits.cny.100")
        XCTAssertNotEqual(other, first)

        IAP.clearIdempotencyKey()
        XCTAssertNotEqual(IAP.takeIdempotencyKey(productId: "credits.cny.100"), other)
        IAP.clearIdempotencyKey()
    }
}
