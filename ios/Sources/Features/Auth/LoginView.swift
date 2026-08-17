import SwiftUI

/// 首屏登录：手机号 + 验证码。注册与登录合一——号码没见过后端就建号，
/// 所以界面上没有「注册」这个词，也没有第二个入口。
struct LoginView: View {
    @Environment(AppModel.self) private var model

    private enum Step { case phone, code }

    @State private var step: Step = .phone
    @State private var phone = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var cooldown = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Eyebrow(text: step == .phone ? "登录" : "验证码")
            Text(step == .phone ? "手机号" : "输入 6 位验证码")
                .font(T.F.display())
                .foregroundStyle(T.L.fg)
                .padding(.top, T.Sp.s2)

            if step == .code {
                Text("已发送至 \(masked)")
                    .font(T.F.micro())
                    .foregroundStyle(T.L.fgFaint)
                    .padding(.top, T.Sp.s1)
            }

            field.padding(.top, T.Sp.s8)
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

    private var masked: String {
        guard phone.count >= 7 else { return phone }
        return phone.prefix(3) + "****" + phone.suffix(4)
    }

    // MARK: - 输入

    @ViewBuilder
    private var field: some View {
        if step == .phone {
            TextField("", text: $phone, prompt: Text("11 位手机号").foregroundStyle(T.L.fgFaint))
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
            Task { step == .phone ? await send() : await verify() }
        } label: {
            HStack {
                Text(step == .phone ? "获取验证码" : "登录")
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
        step == .phone ? phone.count == 11 : code.count == 6
    }

    private var secondaryActions: some View {
        HStack(spacing: T.Sp.s5) {
            Button(cooldown > 0 ? "重新发送 \(cooldown)s" : "重新发送") {
                Task { await send() }
            }
            .disabled(cooldown > 0 || busy)
            .font(T.F.small())
            .foregroundStyle(cooldown > 0 ? T.L.fgFaint : T.L.accent)

            Button("换个号码") {
                withAnimation(T.A.base) { step = .phone; code = ""; error = nil }
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
            Text("收不到验证码？发邮件到 hi@aiworkdeck.com")
                .font(T.F.nano())
                .foregroundStyle(T.L.fgFaint)
                .padding(.top, T.Sp.s3)
        }
        .padding(.bottom, T.Sp.s6)
    }

    private func send() async {
        busy = true; error = nil
        do {
            try await API.shared.sendLoginCode(phone: phone)
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
            let r = try await API.shared.verifyLoginCode(phone: phone, code: code)
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
