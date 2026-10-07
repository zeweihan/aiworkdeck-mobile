import Foundation

/// One workspace retains one login snapshot for every step, including ACK and retries.
struct ProjectFilesContext: Sendable {
    let baseURL: URL
    let sessionID: String
    let language: String
}

struct RemoteProjectFile: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let size: Int64
}

struct ProjectFileListing: Sendable {
    let files: [RemoteProjectFile]
    let count: Int
    let totalCount: Int?
    let truncated: Bool

    init(files: [RemoteProjectFile], count: Int? = nil, totalCount: Int? = nil, truncated: Bool? = nil) {
        self.files = files
        self.count = count ?? files.count
        self.totalCount = totalCount
        // Old desktops and servers returned no metadata at their 2,000-file ceiling.
        self.truncated = truncated ?? (files.count >= 2000)
    }
}

struct ProjectFileQuote: Decodable, Sendable {
    let credits: Int
    let balanceCents: Int64?
}

/// Confirmed server terminal state: a later transfer needs a new quote and explicit consent.
struct ProjectFileTerminalError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// Keep this value for retry. Creating it is local; download creates the charged PULL.
struct ProjectFilePull: Codable, Sendable {
    let project: RelayProject
    let file: RemoteProjectFile
    let requestID: UUID

    init(project: RelayProject, file: RemoteProjectFile, requestID: UUID = UUID()) {
        self.project = project
        self.file = file
        self.requestID = requestID
    }
}

protocol ProjectFilesServing: Sendable {
    func projects() async throws -> [RelayProject]
    func files(in project: RelayProject) async throws -> ProjectFileListing
    func quote(for file: RemoteProjectFile) async throws -> ProjectFileQuote
    /// Persists an account-isolated UUID before a charged request can be sent.
    func preparePull(project: RelayProject, file: RemoteProjectFile) async throws -> ProjectFilePull
    /// Call only after the user accepts the quote. Repeat the same pull to retry.
    func download(_ pull: ProjectFilePull) async throws -> URL
    func cancel(_ pull: ProjectFilePull) async throws
    func removePreview(_ url: URL) async
    func close() async
}
