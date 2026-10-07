import Foundation

/// Values only: no capture devices, image buffers, or user storage are touched here.
struct DualFrameStamp: Codable, Equatable, Sendable {
    let ptsValue: Int64
    let ptsTimescale: Int32
    let ptsEpoch: Int64
    /// Converted from the capture session synchronization clock to the host clock.
    let hostSeconds: Double?
    let dropped: Bool

    var isValid: Bool {
        ptsTimescale > 0 && hostSeconds?.isFinite == true
    }
}

struct DualFramePair: Codable, Equatable, Sendable {
    let requestID: UUID
    let generation: UUID
    let requestedAtHostSeconds: Double
    let acceptedAtHostSeconds: Double
    let rear: DualFrameStamp
    let front: DualFrameStamp
    let maximumSkewSeconds: Double
    let maximumAgeSeconds: Double

    var skewSeconds: Double { abs(rear.hostSeconds! - front.hostSeconds!) }
}

/// The diagnostic prototype accepts only new frames after a shutter request.
/// These limits are prototype policy, not a claim of simultaneous sensor exposure.
struct DualFramePairGate {
    struct Request: Equatable, Sendable {
        let id: UUID
        let generation: UUID
        let hostSeconds: Double
    }

    enum Rejection: String, Equatable {
        case noRequest, differentRequest, differentSession, missingFrame, droppedFrame
        case invalidTimestamp, beforeShutter, futureTimestamp, staleFrame, excessiveSkew
        case timedOut
    }

    enum Decision: Equatable {
        case accepted(DualFramePair)
        case rejected(Rejection)
    }

    static let maximumSkewSeconds = 0.035
    static let maximumAgeSeconds = 0.25
    static let timeoutSeconds = 3.0
    private(set) var request: Request?

    mutating func arm(_ request: Request) { self.request = request }
    mutating func cancel() { request = nil }

    mutating func evaluate(requestID: UUID, generation: UUID,
                           rear: DualFrameStamp?, front: DualFrameStamp?,
                           now: Double) -> Decision {
        guard let request else { return .rejected(.noRequest) }
        guard request.id == requestID else { return .rejected(.differentRequest) }
        guard request.generation == generation else { return .rejected(.differentSession) }
        guard now.isFinite, request.hostSeconds.isFinite else { return .rejected(.invalidTimestamp) }
        guard now - request.hostSeconds <= Self.timeoutSeconds else {
            self.request = nil
            return .rejected(.timedOut)
        }
        guard let rear, let front else { return .rejected(.missingFrame) }
        guard !rear.dropped, !front.dropped else { return .rejected(.droppedFrame) }
        guard rear.isValid, front.isValid,
              let rearTime = rear.hostSeconds, let frontTime = front.hostSeconds else {
            return .rejected(.invalidTimestamp)
        }
        guard rearTime >= request.hostSeconds, frontTime >= request.hostSeconds else {
            return .rejected(.beforeShutter)
        }
        guard rearTime <= now, frontTime <= now else { return .rejected(.futureTimestamp) }
        guard now - rearTime <= Self.maximumAgeSeconds, now - frontTime <= Self.maximumAgeSeconds else {
            return .rejected(.staleFrame)
        }
        guard abs(rearTime - frontTime) <= Self.maximumSkewSeconds else {
            return .rejected(.excessiveSkew)
        }
        self.request = nil
        return .accepted(DualFramePair(requestID: request.id, generation: request.generation,
            requestedAtHostSeconds: request.hostSeconds, acceptedAtHostSeconds: now,
            rear: rear, front: front, maximumSkewSeconds: Self.maximumSkewSeconds,
            maximumAgeSeconds: Self.maximumAgeSeconds))
    }
}
