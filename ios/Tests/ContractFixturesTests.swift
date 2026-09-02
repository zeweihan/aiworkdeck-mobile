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

    func testL10nLocaleSwitchesToEnglish() {
        L10n.locale = "en"
        defer { L10n.locale = "zh-Hans" }
        XCTAssertEqual(tr("phase.landed"), "Landed")
    }
}
