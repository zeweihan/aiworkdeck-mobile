import Foundation
import Security

/// 后端地址。国际版与大陆版是同一套代码，只换这个值和签名 Team——
/// 所以绝不能写死在调用点上。
enum Backend {
    /// **当前指大陆站。**
    ///
    /// 手机号验证码登录只在大陆站可用——国际站没有短信通道（Twilio 未开、
    /// 阿里云国际短信未开通），那边按设计走邮箱验证码。指到国际站的话
    /// `sms-login/send-code` 会因为网关未启用而失败，不是 bug 是设计。
    ///
    /// 国际版要能用，得先做邮箱验证码登录界面；在那之前这个值不该改。
    static let baseURL = URL(string: "https://addin.aiworkdeck.com")!

    /// 国际站。等移动端有了邮箱登录界面再切过去。
    static let internationalURL = URL(string: "https://addin.workdeck.ai")!
}

// MARK: - 会话存储

/// 会话令牌存 Keychain，不存 UserDefaults——那是凭据，不是偏好。
/// UserDefaults 明文躺在沙盒里，设备被解锁取证时一览无余。
enum SessionStore {
    private static let service = "com.aiworkdeck.mobile.session"
    private static let account = "sessionId"

    static var current: String? {
        get { read() }
        set {
            if let newValue { write(newValue) } else { clear() }
        }
    }

    private static func read() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        clear()
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            // 只在本机解锁后可读，且不同步到 iCloud 钥匙串——
            // 尽调设备的会话不该跟着 Apple ID 漂到别的设备上。
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func clear() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - 客户端

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 后端返回的统一信封：{ code, message, data }。code 0 才是成功。
private struct Envelope<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: T?
}

private struct Empty: Decodable {}

/// 两条登录路径共用一个结果形状。手机号那条回 `isNewUser`（号码没见过就建号），
/// 邮箱那条回 `mustBindPhone` 而没有 `isNewUser`——都做成可选，别为差一个字段拆两个类型。
struct LoginResult: Decodable {
    let sessionId: String
    let isNewUser: Bool?
    let mustBindPhone: Bool?
    let user: AccountUser
}

/// 项目目录条目（GET /api/mobile/projects）。**这是桌面端推上云的目录镜像**，
/// key 是那台桌面机本地库的项目 id——跨机同号不同物，所以必须连着 deviceId 一起用，
/// 上传时两个都要带。spec：docs/specs/2026-08-20-project-sync-relay.md。
struct RelayProject: Decodable, Identifiable, Hashable, Sendable, Encodable {
    let deviceId: String
    let deviceName: String?
    let key: String
    let name: String

    var id: String { deviceId + ":" + key }
}

struct CodeOnly: Decodable {
    let code: Int
    let message: String?
}

struct AccountUser: Decodable {
    let id: Int
    let username: String
    let displayName: String
    let avatarUrl: String
    let role: String
}

actor API {
    static let shared = API()

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    // MARK: 登录

    func sendLoginCode(phone: String) async throws {
        _ = try await post("/api/auth/sms-login/send-code",
                           body: ["phone": phone], as: Empty.self)
    }

    func verifyLoginCode(phone: String, code: String) async throws -> LoginResult {
        let r = try await post("/api/auth/sms-login/verify",
                               body: ["phone": phone, "code": code], as: LoginResult.self)
        guard let r else { throw APIError(message: "登录响应缺少数据") }
        SessionStore.current = r.sessionId
        return r
    }

    /// 邮箱验证码登录发码。**只对已注册且已验证邮箱的账号发信**——后端对未注册地址
    /// 同样返回成功（不发信），免得这个匿名端点变成账号枚举器。所以「点了没收到」
    /// 既可能是没注册，也可能是投递慢，界面上不能替后端断言是哪一种。
    func sendMailLoginCode(email: String) async throws {
        _ = try await post("/api/auth/mail-login/send-code",
                           body: ["email": email], as: Empty.self)
    }

    func verifyMailLoginCode(email: String, code: String) async throws -> LoginResult {
        let r = try await post("/api/auth/mail-login/verify",
                               body: ["email": email, "code": code], as: LoginResult.self)
        guard let r else { throw APIError(message: "登录响应缺少数据") }
        SessionStore.current = r.sessionId
        return r
    }

    /// 清会话只碰 Keychain，不需要进 actor 排队——登出必须是立刻生效的同步操作，
    /// 排在别的网络请求后面等于「点了登出还在登录状态」。
    nonisolated func logout() {
        SessionStore.current = nil
    }

    // MARK: 项目与上传

    /// 项目目录（桌面端推上云的镜像）。**返回裸数组，不带 {code,message,data} 信封**，
    /// 与 auth 那几个端点的形状不一样——照信封解会直接失败。
    /// 空数组的最常见原因不是 bug：桌面端没开着、或桌面端还没登录同一个账号。
    func myProjects() async throws -> [RelayProject] {
        try await getRaw("/api/mobile/projects", as: [RelayProject].self)
    }

    /// 上传一件现场影像到中转区（POST /api/mobile/media，单步 multipart）。
    /// 幂等键是 clientMediaId：弱网重传、进程被杀重启都不会在中转区产生重复件，
    /// 所以这里不需要「先建记录再传字节」的两段式。
    func upload(item: CaptureItem, project: RelayProject, fileName: String,
                progress: @Sendable @escaping (Double) -> Void) async throws {
        var req = URLRequest(url: Backend.baseURL.appendingPathComponent("/api/mobile/media"))
        req.httpMethod = "POST"
        let boundary = "awd-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let sid = SessionStore.current { req.setValue(sid, forHTTPHeaderField: "X-Session-Id") }

        let iso = ISO8601DateFormatter()
        // 三分支写死：录音落成 "video" 会被桌面端当录像归档，静默错档比报错更糟。
        let mediaType = switch item.kind {
        case .photo: "image"
        case .video: "video"
        case .audio: "audio"
        }
        let fields: [(String, String)] = [
            ("deviceId", project.deviceId),
            ("projectKey", project.key),
            ("clientMediaId", item.manifest.clientMediaId.uuidString.lowercased()),
            ("fileName", fileName),
            ("mediaType", mediaType),
            ("capturedAt", iso.string(from: item.capturedAt)),
        ]

        // 用 fromFile 而不是把整份读进内存：现场录像几百 MB，读进内存会被系统杀掉。
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("up-\(UUID().uuidString)")
        try makeMultipartFile(at: tmp, boundary: boundary, fields: fields,
                              source: item.localURL, uploadName: fileName)
        defer { try? FileManager.default.removeItem(at: tmp) }

        progress(0.05)
        let (data, resp) = try await session.upload(for: req, fromFile: tmp)
        progress(1)

        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let sc = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError(message: "上传失败（\(sc)）")
        }
        // 后端这条返回 {code,...}；code 非 0 也算失败
        if let env = try? JSONDecoder().decode(CodeOnly.self, from: data), env.code != 0 {
            throw APIError(message: env.message ?? "上传被拒绝")
        }
    }

    struct MediaStatus: Decodable, Sendable {
        let clientMediaId: String
        let delivered: Bool
        let waitingSeconds: Int64
        /// 中转区到期时刻（ISO 本地时间字符串，仅未投递件有）。到期未取回即清理。
        let expiresAt: String?
    }

    struct MediaUsage: Decodable, Sendable {
        let usedBytes: Int64
        let quotaBytes: Int64
    }

    /// 云端中转区用量（GET /api/mobile/media/usage）。裸对象，无信封。
    func mediaUsage() async throws -> MediaUsage {
        try await getRaw("/api/mobile/media/usage", as: MediaUsage.self)
    }

    /// 影像投递状态：delivered = 桌面端已确认落盘（中转区已删）。裸数组。
    func mediaStatus(clientMediaIds: [String]) async throws -> [MediaStatus] {
        guard !clientMediaIds.isEmpty else { return [] }
        var comps = URLComponents(url: Backend.baseURL.appendingPathComponent("/api/mobile/media/status"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "clientMediaIds", value: clientMediaIds.joined(separator: ","))]
        var req = URLRequest(url: comps.url!)
        if let sid = SessionStore.current { req.setValue(sid, forHTTPHeaderField: "X-Session-Id") }
        let (data, resp) = try await send(req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError(message: "服务器返回 \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        do { return try JSONDecoder().decode([MediaStatus].self, from: data) }
        catch { throw APIError(message: "无法解析服务器响应") }
    }

    /// 把 multipart 信封写成磁盘文件，避免整份载荷进内存。
    /// 文本字段在前、文件在后——服务端流式解析时先拿到寻址字段。
    private nonisolated func makeMultipartFile(at dst: URL, boundary: String,
                                               fields: [(String, String)],
                                               source: URL, uploadName: String) throws {
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let h = try FileHandle(forWritingTo: dst)
        defer { try? h.close() }
        for (name, value) in fields {
            let part = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
            try h.write(contentsOf: Data(part.utf8))
        }
        let head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(uploadName)\"\r\nContent-Type: application/octet-stream\r\n\r\n"
        try h.write(contentsOf: Data(head.utf8))
        let r = try FileHandle(forReadingFrom: source)
        defer { try? r.close() }
        while let chunk = try r.read(upToCount: 1 << 20), !chunk.isEmpty {
            try h.write(contentsOf: chunk)
        }
        try h.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }

    // MARK: 传输

    /// 裸响应（无信封）的 GET。
    private func getRaw<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var req = URLRequest(url: Backend.baseURL.appendingPathComponent(path))
        if let sid = SessionStore.current { req.setValue(sid, forHTTPHeaderField: "X-Session-Id") }
        let (data, resp) = try await send(req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError(message: "服务器返回 \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError(message: "无法解析服务器响应") }
    }

    /// 裸响应（无信封）的 POST。
    private func postRaw<T: Decodable>(_ path: String, body: [String: Any],
                                       as type: T.Type) async throws -> T {
        var req = URLRequest(url: Backend.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sid = SessionStore.current { req.setValue(sid, forHTTPHeaderField: "X-Session-Id") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await send(req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError(message: "服务器返回 \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError(message: "无法解析服务器响应") }
    }

    private func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: req) }
        catch { throw APIError(message: "连不上服务器，检查网络后重试") }
    }

    private func post<T: Decodable>(_ path: String,
                                    body: [String: String],
                                    as type: T.Type) async throws -> T? {
        var req = URLRequest(url: Backend.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sid = SessionStore.current {
            req.setValue(sid, forHTTPHeaderField: "X-Session-Id")
        }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            // 网络层失败要与业务失败分开说。用户看到「验证码错误」和看到
            // 「连不上服务器」会做完全不同的事。
            throw APIError(message: "连不上服务器，检查网络后重试")
        }

        guard let http = resp as? HTTPURLResponse else {
            throw APIError(message: "服务器响应异常")
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError(message: "服务器返回 \(http.statusCode)")
        }

        let env: Envelope<T>
        do {
            env = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            throw APIError(message: "无法解析服务器响应")
        }
        guard env.code == 0 else {
            throw APIError(message: env.message ?? "操作失败")
        }
        return env.data
    }
}
