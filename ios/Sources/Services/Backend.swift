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

struct LoginResult: Decodable {
    let sessionId: String
    let isNewUser: Bool
    let user: AccountUser
}

/// 项目卡片。后端 ProjectCardDTO 字段远比这里多，只声明用得到的——
/// 多余的键 JSONDecoder 会安全忽略。
struct ProjectSummary: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let myRole: String?
}

/// 建文件记录的返回。
struct RemoteFile: Decodable {
    let id: Int
    let name: String
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

    /// 清会话只碰 Keychain，不需要进 actor 排队——登出必须是立刻生效的同步操作，
    /// 排在别的网络请求后面等于「点了登出还在登录状态」。
    nonisolated func logout() {
        SessionStore.current = nil
    }

    // MARK: 项目与上传

    /// 账号下的项目。**注意这个端点返回裸数组，不带 {code,message,data} 信封**，
    /// 与 auth 那几个端点的形状不一样——照信封解会直接失败。
    func myProjects() async throws -> [ProjectSummary] {
        try await getRaw("/api/projects/my", as: [ProjectSummary].self)
    }

    /// 上传是两段式：先建文件记录拿 id，再把字节 PUT 进去。
    /// 分成两段的好处是断点续传时不用重建记录，坏处是中途失败会留下空记录——
    /// 所以建记录放在真正要传的那一刻，不提前批量建。
    func upload(item: CaptureItem, projectId: Int, fileName: String,
                progress: @Sendable @escaping (Double) -> Void) async throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: item.localURL.path)[.size] as? Int64) ?? 0
        let record = try await postRaw("/api/projects/\(projectId)/files/file",
                                       body: ["name": fileName,
                                              "fileType": item.kind == .photo ? "image" : "video",
                                              "fileSize": String(size ?? 0)],
                                       as: RemoteFile.self)
        try await putBytes(fileId: record.id, from: item.localURL, progress: progress)
    }

    private func putBytes(fileId: Int, from url: URL,
                          progress: @Sendable @escaping (Double) -> Void) async throws {
        var req = URLRequest(url: Backend.baseURL.appendingPathComponent("/api/files/\(fileId)/upload"))
        req.httpMethod = "POST"
        let boundary = "awd-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let sid = SessionStore.current { req.setValue(sid, forHTTPHeaderField: "X-Session-Id") }

        // 用 fromFile 而不是把整份读进内存：现场录像几百 MB，读进内存会被系统杀掉。
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("up-\(UUID().uuidString)")
        try makeMultipartFile(at: tmp, boundary: boundary, source: url)
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

    /// 把 multipart 信封写成磁盘文件，避免整份载荷进内存。
    private nonisolated func makeMultipartFile(at dst: URL, boundary: String, source: URL) throws {
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let h = try FileHandle(forWritingTo: dst)
        defer { try? h.close() }
        let head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(source.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n"
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
    private func postRaw<T: Decodable>(_ path: String, body: [String: String],
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
