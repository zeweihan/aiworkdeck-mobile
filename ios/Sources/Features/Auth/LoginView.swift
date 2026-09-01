import SwiftUI

/// 首屏登录：手机号或邮箱 + 验证码。
///
/// 两条路径**语义不同**，界面上必须说清，别做成同一句话换个输入框：
/// - 手机号：注册与登录合一，号码没见过后端就建号。只走中国大陆短信通道。
/// - 邮箱：**只登录，不建号**。后端 mail-login 对未注册地址照样回成功但不发信
///   （防账号枚举），所以「没收到」既可能是没注册也可能是投递慢，我们不能替
///   后端断言是哪一种——只能在页脚把注册入口摆出来。
///
/// 邮箱这条是国际版能用的前提：境外收不到中国短信，只有手机号那条等于门是锁死的。
struct LoginView: View {
    @Environment(AppModel.self) private var model

    private enum Method { case phone, email }
    private enum Step { case identity, code }

    /// 进门先看见哪一种。
    ///
    /// 短信通道只有阿里云的大陆签名，**发不到境外号码**，所以国际版默认邮箱：
    /// 让海外用户一进门就对着一个填不了的手机号框，是在浪费他一次尝试。
    /// 手机号那条对国际版仍然留着——带 +86 号码的人在境外照样收得到码，
    /// 那是国际版的主要人群之一，砍掉等于把他们挡在门外。
    private static var defaultMethod: Method {
        Bundle.main.bundleIdentifier == "com.aiworkdeck.mobile.cn" ? .phone : .email
    }

    @State private var method: Method = LoginView.defaultMethod
    @State private var step: Step = .identity
    @State private var phone = ""
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var cooldown = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Eyebrow(text: step == .identity ? "登录" : "验证码")
            Text(title)
                .font(T.F.display())
                .foregroundStyle(T.L.fg)
                .padding(.top, T.Sp.s2)

            if step == .code {
                Text("已发送至 \(masked)")
                    .font(T.F.micro())
                    .foregroundStyle(T.L.fgFaint)
                    .padding(.top, T.Sp.s1)
            }

            if step == .identity { methodPicker.padding(.top, T.Sp.s4) }

            field.padding(.top, step == .identity ? T.Sp.s5 : T.Sp.s8)
            Hairline().padding(.top, T.Sp.s3)

            if let error {
                Text(error)
                    .font(T.F.micro())
                    .foregroundStyle(T.S.failed)
                    .padding(.top, T.Sp.s3)
                    .transition(.opacity)
            }

            primaryAction.padding(.top, T.Sp.s6)

            if step == .code { secondaryActions.padding(.top, T.Sp.s4) }

            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, T.Sp.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(T.L.bg)
        .onAppear { focused = true }
    }

    private var title: String {
        if step == .code { return "输入 6 位验证码" }
        return method == .phone ? "手机号" : "邮箱"
    }

    private var masked: String {
        switch method {
        case .phone:
            guard phone.count >= 7 else { return phone }
            return phone.prefix(3) + "****" + phone.suffix(4)
        case .email:
            guard let at = email.firstIndex(of: "@") else { return email }
            let name = email[email.startIndex..<at]
            let head = name.count <= 1 ? "***" : name.prefix(1) + "***"
            return head + email[at...]
        }
    }

    // MARK: - 输入

    /// 两个方式之间切换。切换要清掉另一路的输入与报错，否则会出现
    /// 「填了邮箱、报的是手机号那条的错」这种对不上号的状态。
    private var methodPicker: some View {
        HStack(spacing: T.Sp.s5) {
            ForEach([Method.phone, Method.email], id: \.self) { m in
                Button {
                    guard method != m else { return }
                    withAnimation(T.A.base) {
                        method = m
                        code = ""
                        error = nil
                    }
                    focused = true
                } label: {
                    Text(m == .phone ? "手机号" : "邮箱")
                        .font(T.F.small())
                        .foregroundStyle(method == m ? T.L.accent : T.L.fgMuted)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(minHeight: T.touchMin)
    }

    @ViewBuilder
    private var field: some View {
        switch step {
        case .identity:
            if method == .phone {
                TextField("", text: $phone, prompt: Text("中国大陆手机号").foregroundStyle(T.L.fgFaint))
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .font(T.F.mono(28, .light))
                    .foregroundStyle(T.L.fg)
                    .focused($focused)
                    .onChange(of: phone) { _, v in
                        phone = String(v.filter(\.isNumber).prefix(11))
                        error = nil
                    }
            } else {
                // 占位符**不能写成一个真邮箱样子的串**：SwiftUI 的 Text 会把它识别成
                // 邮件链接、按 accent 色渲染，看上去像是已经填好了值（页脚那条
                // hi@aiworkdeck.com 的蓝色就是同一个机制，那处是有意的）。
                TextField("", text: $email, prompt: Text("邮箱地址").foregroundStyle(T.L.fgFaint))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(T.F.mono(20, .light))
                    .foregroundStyle(T.L.fg)
                    .focused($focused)
                    .onChange(of: email) { _, v in
                        email = v.trimmingCharacters(in: .whitespaces)
                        error = nil
                    }
            }
        case .code:
            TextField("", text: $code, prompt: Text("······").foregroundStyle(T.L.fgFaint))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)   // 让系统从短信里自动填
                .font(T.F.mono(28, .light))
                .tracking(8)
                .foregroundStyle(T.L.fg)
                .focused($focused)
                .onChange(of: code) { _, v in
                    code = String(v.filter(\.isNumber).prefix(6))
                    error = nil
                    if code.count == 6 { Task { await verify() } }   // 满 6 位自动提交
                }
        }
    }

    // MARK: - 动作

    private var primaryAction: some View {
        Button {
            Task { step == .identity ? await send() : await verify() }
        } label: {
            HStack {
                Text(step == .identity ? "获取验证码" : "登录")
                    .font(T.F.heading())
                    .foregroundStyle(canSubmit ? T.L.accent : T.L.fgFaint)
                Spacer()
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canSubmit ? T.L.accent : T.L.fgFaint)
                }
            }
            .frame(minHeight: T.touchMin)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || busy)
    }

    private var canSubmit: Bool {
        switch step {
        case .identity: return method == .phone ? phone.count == 11 : looksLikeEmail
        case .code:     return code.count == 6
        }
    }

    /// 只做「明显不是邮箱」的拦截，不做 RFC 校验——真正的判定在后端，
    /// 客户端把合法地址挡下来比放个错地址过去更糟。
    private var looksLikeEmail: Bool {
        guard let at = email.firstIndex(of: "@"), at != email.startIndex else { return false }
        let domain = email[email.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    private var secondaryActions: some View {
        HStack(spacing: T.Sp.s5) {
            Button(cooldown > 0 ? "重新发送 \(cooldown)s" : "重新发送") {
                Task { await send() }
            }
            .disabled(cooldown > 0 || busy)
            .font(T.F.small())
            .foregroundStyle(cooldown > 0 ? T.L.fgFaint : T.L.accent)

            Button(method == .phone ? "换个号码" : "换个邮箱") {
                withAnimation(T.A.base) { step = .identity; code = ""; error = nil }
                focused = true
            }
            .font(T.F.small())
            .foregroundStyle(T.L.fgMuted)

            Spacer()
        }
        .frame(minHeight: T.touchMin)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: T.Sp.s1) {
            Hairline()
            // 邮箱这条只登录不建号，所以必须给出注册在哪——否则新用户填了邮箱、
            // 等不到信，也不知道下一步该去哪。
            if method == .email {
                Text("邮箱登录用于已有 AI WorkDeck 账号。还没有账号请先到 aiworkdeck.com 注册。")
                    .font(T.F.nano())
                    .foregroundStyle(T.L.fgFaint)
                    .padding(.top, T.Sp.s3)
            }
            Text("收不到验证码？发邮件到 hi@aiworkdeck.com")
                .font(T.F.nano())
                .foregroundStyle(T.L.fgFaint)
                .padding(.top, method == .email ? T.Sp.s1 : T.Sp.s3)
        }
        .padding(.bottom, T.Sp.s6)
    }

    private func send() async {
        busy = true; error = nil
        do {
            switch method {
            case .phone: try await API.shared.sendLoginCode(phone: phone)
            case .email: try await API.shared.sendMailLoginCode(email: email)
            }
            withAnimation(T.A.base) { step = .code }
            code = ""
            focused = true
            startCooldown()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func verify() async {
        guard !busy else { return }
        busy = true; error = nil
        do {
            let r = switch method {
            case .phone: try await API.shared.verifyLoginCode(phone: phone, code: code)
            case .email: try await API.shared.verifyMailLoginCode(email: email, code: code)
            }
            await model.didLogin(r)
        } catch {
            self.error = error.localizedDescription
            code = ""
        }
        busy = false
    }

    /// 60 秒重发冷却。后端也有冷却，这里只是别让人白点。
    private func startCooldown() {
        cooldown = 60
        Task {
            while cooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                cooldown -= 1
            }
        }
    }
}
