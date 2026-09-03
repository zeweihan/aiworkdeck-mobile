import XCTest
@testable import Workdeck

/// 录音时钟：录音舞台的计时器与 Live Activity 的内容状态都从它派生，两处不会各算各的。
final class RecordingClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testNotStartedIsZero() {
        let c = RecordingClock()
        XCTAssertEqual(c.elapsed(at: at(100)), 0)
        XCTAssertFalse(c.paused)
        XCTAssertNil(c.resumedAt)
    }

    func testRunningCountsFromStart() {
        var c = RecordingClock()
        c.start(at: t0)
        XCTAssertEqual(c.elapsed(at: at(12)), 12)
        XCTAssertEqual(c.elapsedBase, 0)
        XCTAssertEqual(c.resumedAt, t0)
        XCTAssertFalse(c.paused)
    }

    func testInterruptFreezesElapsed() {
        var c = RecordingClock()
        c.start(at: t0)
        c.interrupt(at: at(30))
        XCTAssertTrue(c.paused)
        XCTAssertNil(c.resumedAt)
        XCTAssertEqual(c.elapsedBase, 30)
        XCTAssertEqual(c.elapsed(at: at(90)), 30)
    }

    func testResumeContinuesFromBase() {
        var c = RecordingClock()
        c.start(at: t0)
        c.interrupt(at: at(30))
        c.resume(at: at(90))
        XCTAssertFalse(c.paused)
        XCTAssertEqual(c.resumedAt, at(90))
        XCTAssertEqual(c.elapsedBase, 30)
        XCTAssertEqual(c.elapsed(at: at(100)), 40)
    }

    func testMultipleInterruptionsAccumulate() {
        var c = RecordingClock()
        c.start(at: t0)
        c.interrupt(at: at(10)); c.resume(at: at(20))
        c.interrupt(at: at(25)); c.resume(at: at(60))
        c.interrupt(at: at(70))
        XCTAssertEqual(c.elapsedBase, 25)   // 10 + 5 + 10
        c.resume(at: at(100))
        XCTAssertEqual(c.elapsed(at: at(103)), 28)
    }

    /// 系统可能连发两次 .began，第二次不能再扣一段
    func testRepeatedInterruptIsIdempotent() {
        var c = RecordingClock()
        c.start(at: t0)
        c.interrupt(at: at(10))
        c.interrupt(at: at(50))
        XCTAssertEqual(c.elapsedBase, 10)
        XCTAssertEqual(c.elapsed(at: at(80)), 10)
    }

    func testResumeWithoutInterruptIsNoop() {
        var c = RecordingClock()
        c.start(at: t0)
        c.resume(at: at(50))
        XCTAssertEqual(c.resumedAt, t0)
        XCTAssertEqual(c.elapsed(at: at(60)), 60)
    }

    func testInterruptBeforeStartIsNoop() {
        var c = RecordingClock()
        c.interrupt(at: at(5))
        XCTAssertFalse(c.paused)
        XCTAssertEqual(c.elapsed(at: at(9)), 0)
    }

    func testStartResetsPreviousRun() {
        var c = RecordingClock()
        c.start(at: t0)
        c.interrupt(at: at(10))
        c.start(at: at(100))
        XCTAssertEqual(c.elapsedBase, 0)
        XCTAssertFalse(c.paused)
        XCTAssertEqual(c.elapsed(at: at(105)), 5)
    }
}
