import XCTest
@testable import Workdeck

/// 契约夹具适配：contract/fixtures/*.json 作为测试 bundle 资源（project.yml 里挂进 WorkdeckTests）。
final class ContractFixturesTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = Bundle(for: Self.self).resourceURL!.appendingPathComponent("fixtures/\(name).json")
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    private func cases(_ name: String) throws -> [[String: Any]] { try fixture(name)["cases"] as! [[String: Any]] }
    private func state(_ s: String) -> TransferState { TransferState(rawValue: s)! }
    /// billing.json 不是 `{cases:[...]}` 结构，是按段名（balance/recharge/status/envelope）
    /// 各自一个数组，取段名而不是 "cases"。
    private func billingSection(_ key: String) throws -> [[String: Any]] { try fixture("billing")[key] as! [[String: Any]] }

    func testTally() throws {
        for k in try cases("tally") {
            let items = (k["states"] as! [String]).map { TestItems.make(state($0)) }
            let t = TransferTally.of(items)
            let e = k["expect"] as! [String: Int]
            XCTAssertEqual(t.uploading, e["uploading"], k["name"] as! String)
            XCTAssertEqual(t.failed, e["failed"], k["name"] as! String)
            XCTAssertEqual(t.staged, e["staged"], k["name"] as! String)
            XCTAssertEqual(t.landed, e["landed"], k["name"] as! String)
            XCTAssertEqual(t.total, e["total"], k["name"] as! String)
        }
    }

    func testTransitions() throws {
        for k in try cases("transitions") {
            let from = state(k["from"] as! String)
            let ev = TransferEvent(rawValue: k["event"] as! String)!
            let got = from.next(ev, attempts: k["attempts"] as! Int)
            let want = (k["to"] as? String).map(state)
            XCTAssertEqual(got, want, "\(from)+\(ev)(\(k["attempts"]!))")
        }
    }

    func testRestore() throws {
        for k in try cases("restore") {
            XCTAssertEqual(state(k["state"] as! String).recovered(attempts: k["attempts"] as! Int), state(k["expect"] as! String))
        }
    }

    func testStatusMerge() throws {
        for k in try cases("status-merge") {
            let st = k["status"] as! [String: Any]
            let got = state(k["state"] as! String).applyingStatus(
                delivered: st["delivered"] as! Bool,
                waitingSeconds: Int64(st["waitingSeconds"] as! Int),
                expiresAt: st["expiresAt"] as? String)
            let e = k["expect"] as! [String: Any]
            XCTAssertEqual(got.state, state(e["state"] as! String), k["name"] as! String)
            XCTAssertEqual(got.waitingSeconds, (e["waitingSeconds"] as? Int).map(Int64.init), k["name"] as! String)
            XCTAssertEqual(got.expiresAt, e["expiresAt"] as? String, k["name"] as! String)
        }
    }

    func testDeleteWarning() throws {
        for k in try cases("delete-warning") {
            let got = LibraryGrouping.deleteWarningLevel((k["states"] as! [String]).map(state))
            let e = k["expect"] as! [String: Any]
            XCTAssertEqual(got.level, e["level"] as! String)
            XCTAssertEqual(got.n, e["n"] as! Int)
        }
    }

    func testLegacyMovingDecodes() throws {
        let decoded = try JSONDecoder().decode([TransferState].self, from: Data(#"["moving","waiting"]"#.utf8))
        XCTAssertEqual(decoded, [.uploading, .waiting])
        let encoded = String(data: try JSONEncoder().encode([TransferState.uploading]), encoding: .utf8)
        XCTAssertEqual(encoded, #"["uploading"]"#)
    }

    func testStringsComeFromContract() {
        XCTAssertEqual(TransferPhase.landed.caption, tr("phase.landed"))
        XCTAssertEqual(TransferState.failed.caption, "上传失败")
        XCTAssertEqual(tr("delete.title", ["n": "3"]), "删除 3 件")
    }

    /// billing.json 的 envelope 段（dev-board#425）：kind 是机器可读判别位，一律按它分支，
    /// 不匹配 message 措辞。缺席的 kind/outTradeNo 必须解成 nil，不是空串；八个 kind
    /// 全部取值都要能解码，一个不缺。
    func testBillingEnvelopeFixtures() throws {
        struct Envelope: Decodable {
            let code: Int
            let message: String?
            let kind: API.BillingKind?
            let outTradeNo: String?
        }
        var seenKinds = Set<String>()
        for k in try billingSection("envelope") {
            let name = k["name"] as! String
            let json = k["json"] as! [String: Any]
            let expect = k["expect"] as! [String: Any]
            let data = try JSONSerialization.data(withJSONObject: json)
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            XCTAssertEqual(env.code, expect["code"] as! Int, name)
            XCTAssertEqual(env.message, expect["message"] as? String, name)
            XCTAssertEqual(env.kind?.rawValue, expect["kind"] as? String, name)
            XCTAssertEqual(env.outTradeNo, expect["outTradeNo"] as? String, name)
            // 键缺席要解成 nil；尤其 outTradeNo 不能被误当成「读到了一个空单号」。
            XCTAssertNotEqual(env.outTradeNo, "", name)
            if let kind = env.kind { seenKinds.insert(kind.rawValue) }
        }
        XCTAssertEqual(seenKinds, Set(API.BillingKind.allCases.map(\.rawValue)),
                       "夹具必须覆盖全部八个 kind")
    }

    /// billing.json 的 balance 段：plan 是计费档位（paid/free/null），不是套餐名。
    /// SettingsView.balanceCaption 只读 balanceCents/currency 拼格式化金额，从不读 plan——
    /// 这里断言解码正确即可，plan 是否被渲染由那处代码本身保证（它压根没有 plan 这个入参）。
    func testBillingBalanceFixtures() throws {
        for k in try billingSection("balance") {
            let name = k["name"] as! String
            let json = k["json"] as! [String: Any]
            let expect = k["expect"] as! [String: Any]
            let data = try JSONSerialization.data(withJSONObject: json)
            let balance = try JSONDecoder().decode(API.BillingBalance.self, from: data)
            XCTAssertEqual(balance.balanceCents, Int64(expect["balanceCents"] as! Int), name)
            XCTAssertEqual(balance.currency, expect["currency"] as! String, name)
            XCTAssertEqual(balance.plan, expect["plan"] as? String, name)
        }
    }

    /// billing.json 的 balance 段驱动 `API.decodeBillingBalance`——这是 `API.billingBalance()`
    /// 真正在用的判读函数，覆盖裸对象分支（二轮复审 N4：以前这段判读代码一行测试都没有覆盖过，
    /// 见 Backend.swift 上 `decodeBillingBalance` 的注释）。
    func testBillingBalanceDecodeFixtures() throws {
        for k in try billingSection("balance") {
            let name = k["name"] as! String
            let json = k["json"] as! [String: Any]
            let expect = k["expect"] as! [String: Any]
            let data = try JSONSerialization.data(withJSONObject: json)
            guard case .ok(let balance) = API.decodeBillingBalance(status: 200, data: data) else {
                XCTFail("\(name)：期望 .ok"); continue
            }
            XCTAssertEqual(balance.balanceCents, Int64(expect["balanceCents"] as! Int), name)
            XCTAssertEqual(balance.currency, expect["currency"] as! String, name)
            XCTAssertEqual(balance.plan, expect["plan"] as? String, name)
        }
    }

    /// billing.json 的 envelope 段驱动同一条生产判读路径，钉住 N2 的映射表（唯一来源见
    /// contract/schema/billing.schema.json）：NOT_CONNECTED / DISABLED / REVIEW_ACCOUNT
    /// 整行不渲染（`.hidden`）；其余（含 kind 缺席）都是 balance.unavailable（`.unavailable`）。
    /// 把 `decodeBillingBalance` 里 `case .notConnected, .disabled, .reviewAccount: return .hidden`
    /// 改坏（比如去掉 `.disabled, .reviewAccount`），这里必须变红——这就是这份测试存在的意义。
    func testBillingBalanceKindMappingFixtures() throws {
        let hiddenKinds: Set<String> = ["NOT_CONNECTED", "DISABLED", "REVIEW_ACCOUNT"]
        for k in try billingSection("envelope") {
            let name = k["name"] as! String
            let json = k["json"] as! [String: Any]
            let kind = json["kind"] as? String
            // ALREADY_PAID / IDEMPOTENCY_CONFLICT 只出现在下单/查单路径，走不到余额端点。
            if kind == "ALREADY_PAID" || kind == "IDEMPOTENCY_CONFLICT" { continue }
            let data = try JSONSerialization.data(withJSONObject: json)
            let result = API.decodeBillingBalance(status: 200, data: data)
            if let kind, hiddenKinds.contains(kind) {
                guard case .hidden = result else { XCTFail("\(name)：kind=\(kind) 应该是 .hidden"); continue }
            } else {
                guard case .unavailable = result else {
                    XCTFail("\(name)：kind=\(kind ?? "nil") 应该是 .unavailable"); continue
                }
            }
        }
    }

    /// billing.json 的 balance 段还钉住金额展示口径本身（二轮复审 N7）：不带千分位、
    /// 固定两位小数、符号按 currency 取、不跟设备 locale 走。参考实现见
    /// contract/tools/check.mjs 的 referenceMoneyDisplay，check.mjs 已经用它复算过夹具的
    /// display 字段，这里只需要拿 SettingsView.formatAmount 与夹具本身对拍。
    func testBillingAmountDisplayFixtures() throws {
        for k in try billingSection("balance") {
            let name = k["name"] as! String
            let json = k["json"] as! [String: Any]
            let display = k["display"] as! String
            let cents = Int64(json["balanceCents"] as! Int)
            let currency = json["currency"] as! String
            XCTAssertEqual(SettingsView.formatAmount(cents: cents, currency: currency), display, name)
        }
    }

    func testL10nLocaleSwitchesToEnglish() {
        L10n.locale = "en"
        defer { L10n.locale = "zh-Hans" }
        XCTAssertEqual(tr("phase.landed"), "Landed")
    }
}
