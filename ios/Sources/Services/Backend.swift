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

    // MARK: 传输

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
