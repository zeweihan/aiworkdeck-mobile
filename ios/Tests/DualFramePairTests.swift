import XCTest
@testable import Workdeck

final class DualFramePairTests: XCTestCase {
    private let requestID = UUID()
    private let generation = UUID()

    private func stamp(_ time: Double, dropped: Bool = false) -> DualFrameStamp {
        DualFrameStamp(ptsValue: Int64(time * 1000), ptsTimescale: 1000, ptsEpoch: 0,
                       hostSeconds: time, dropped: dropped)
    }

    private func armed(at time: Double = 100) -> DualFramePairGate {
        var gate = DualFramePairGate()
        gate.arm(.init(id: requestID, generation: generation, hostSeconds: time))
        return gate
    }

    private func evaluate(_ gate: inout DualFramePairGate, rear: DualFrameStamp? = nil,
                          front: DualFrameStamp? = nil, now: Double = 100.2) -> DualFramePairGate.Decision {
        gate.evaluate(requestID: requestID, generation: generation, rear: rear, front: front, now: now)
    }

    func testFreshPairPreservesBothTimestampsAndConsumesRequestOnce() {
        var gate = armed()
        guard case .accepted(let pair) = evaluate(&gate, rear: stamp(100.1), front: stamp(100.12)) else {
            return XCTFail("Expected a fresh pair")
        }
        XCTAssertEqual(pair.requestID, requestID)
        XCTAssertEqual(pair.generation, generation)
        XCTAssertEqual(pair.rear.ptsValue, 100100)
        XCTAssertEqual(pair.front.ptsValue, 100120)
        XCTAssertEqual(pair.skewSeconds, 0.02, accuracy: 0.000001)
        XCTAssertEqual(pair.requestedAtHostSeconds, 100)
        XCTAssertNil(gate.request)
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.15), front: stamp(100.15)), .rejected(.noRequest))
    }

    func testEitherMissingOutputDoesNotConsumeRequest() {
        var gate = armed()
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.1)), .rejected(.missingFrame))
        XCTAssertEqual(evaluate(&gate, front: stamp(100.1)), .rejected(.missingFrame))
        XCTAssertNotNil(gate.request)
    }

    func testDroppedBufferOnEitherCameraIsRejected() {
        var gate = armed()
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.1, dropped: true), front: stamp(100.1)), .rejected(.droppedFrame))
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.1), front: stamp(100.1, dropped: true)), .rejected(.droppedFrame))
    }

    func testCachedFrameBeforeShutterCannotBePairedWithNewFrame() {
        var gate = armed()
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.01), front: stamp(99.99)), .rejected(.beforeShutter))
    }

    func testOldButPostShutterPairIsRejected() {
        var gate = armed()
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.1), front: stamp(100.1), now: 100.4), .rejected(.staleFrame))
    }

    func testFutureTimestampIsRejected() {
        var gate = armed()
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.3), front: stamp(100.3)), .rejected(.futureTimestamp))
    }

    func testExcessiveSkewIsRejectedEvenWhenBothFramesAreFresh() {
        var gate = armed()
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.1), front: stamp(100.15)), .rejected(.excessiveSkew))
    }

    func testInvalidTimescaleAndNonfiniteHostClockAreRejected() {
        var gate = armed()
        let invalid = DualFrameStamp(ptsValue: 0, ptsTimescale: 0, ptsEpoch: 0, hostSeconds: 100.1, dropped: false)
        XCTAssertEqual(evaluate(&gate, rear: invalid, front: stamp(100.1)), .rejected(.invalidTimestamp))
        for value in [Double.nan, Double.infinity] {
            let frame = DualFrameStamp(ptsValue: 100, ptsTimescale: 1, ptsEpoch: 0, hostSeconds: value, dropped: false)
            XCTAssertEqual(evaluate(&gate, rear: stamp(100.1), front: frame), .rejected(.invalidTimestamp))
        }
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.1), front: stamp(100.1), now: .nan), .rejected(.invalidTimestamp))
    }

    func testUnavailableClockConversionIsRejected() {
        var gate = armed()
        let frame = DualFrameStamp(ptsValue: 100, ptsTimescale: 1, ptsEpoch: 0, hostSeconds: nil, dropped: false)
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.1), front: frame), .rejected(.invalidTimestamp))
    }

    func testExpiredRequestIsConsumedWithoutAcceptingNewFrames() {
        var gate = armed()
        XCTAssertEqual(evaluate(&gate, rear: stamp(103.05), front: stamp(103.05), now: 103.1), .rejected(.timedOut))
        XCTAssertNil(gate.request)
    }

    func testOldCallbackCannotCompleteReplacementRequest() {
        var gate = armed()
        let replacement = UUID()
        gate.arm(.init(id: replacement, generation: generation, hostSeconds: 100.05))
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.1), front: stamp(100.1)), .rejected(.differentRequest))
        XCTAssertEqual(gate.request?.id, replacement)
    }

    func testPreviousSessionCannotCompleteCurrentRequest() {
        var gate = armed()
        XCTAssertEqual(gate.evaluate(requestID: requestID, generation: UUID(),
            rear: stamp(100.1), front: stamp(100.1), now: 100.2), .rejected(.differentSession))
        XCTAssertNotNil(gate.request)
    }

    func testRejectedPairCanBeFollowedByFirstValidPairAndCancelIsFinal() {
        var gate = armed()
        XCTAssertEqual(evaluate(&gate, rear: stamp(99.99), front: stamp(100.01)), .rejected(.beforeShutter))
        guard case .accepted = evaluate(&gate, rear: stamp(100.1), front: stamp(100.1)) else {
            return XCTFail("Rejection must not consume an active request")
        }
        gate = armed()
        gate.cancel()
        XCTAssertEqual(evaluate(&gate, rear: stamp(100.1), front: stamp(100.1)), .rejected(.noRequest))
    }
}
