import Foundation

/// A shutter owns its callbacks even if another capture screen replaces the
/// service's current UI callbacks before AVFoundation finishes processing.
@MainActor
struct CameraCaptureRequests {
    struct Request {
        let capturedAt: Date
        let completed: ((Data, MediaKind, Date) -> Void)?
        let failed: ((String) -> Void)?
    }
    private var requests: [Int64: Request] = [:]
    var isEmpty: Bool { requests.isEmpty }
    mutating func begin(id: Int64, at: Date, completed: ((Data, MediaKind, Date) -> Void)?, failed: ((String) -> Void)?) {
        requests[id] = Request(capturedAt: at, completed: completed, failed: failed)
    }
    mutating func take(id: Int64) -> Request? { requests.removeValue(forKey: id) }
}

/// A stop or newer start invalidates an earlier asynchronous permission/configuration result.
struct CameraStartIntent {
    private(set) var generation = UUID()
    private(set) var wantsRunning = false
    mutating func begin() -> UUID { generation = UUID(); wantsRunning = true; return generation }
    mutating func stop() { generation = UUID(); wantsRunning = false }
    func accepts(_ token: UUID) -> Bool { wantsRunning && generation == token }
}
