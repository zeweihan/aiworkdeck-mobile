import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    var onClose: () -> Void

    @State private var saveToAlbum = Prefs.saveToAlbum
    @State private var albumError: String?
    @State private var usage: API.MediaUsage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    group(tr("settings.media")) {
                        Toggle(isOn: $saveToAlbum) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("settings.saveToAlbum"))
                                    .font(T.F.body())
                                    .foregroundStyle(T.L.fg)
                                // 把权衡摆在这儿，让每次选择都是知情的。
                                // 这不是吓唬人——尽调影像进相册，手机丢了或被查时
                                // 它就躺在那儿。
                                Text(tr("settings.saveToAlbum.hint"))
                                    .font(T.F.nano())
                                    .foregroundStyle(T.L.fgFaint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(T.L.accent)
                        .onChange(of: saveToAlbum) { _, v in
                            Prefs.saveToAlbum = v
                            if v { Task { await requestAlbumPermission() } }
                        }

                        if let albumError {
                            Text(albumError)
                                .font(T.F.nano())
                                .foregroundStyle(T.S.failed)
                                .padding(.top, T.Sp.s2)
                        }

                        infoRow("本地原图", "上传成功后不会自动删除。现场不可复现，我们不替你做这个决定。")
                    }

                    group(tr("settings.archiveTarget")) {
                        infoRow(tr("home.eyebrow"), model.project.name)
                        infoRow(tr("settings.relay"), usageCaption)
                        Button(tr("settings.switchProject")) { model.clearProjectSelection() }
                            .font(T.F.small())
                            .foregroundStyle(T.L.accent)
                            .frame(minHeight: T.touchMin, alignment: .leading)
                    }

                    group(tr("settings.account")) {
                        infoRow(tr("settings.signedIn"), model.account?.displayName ?? "—")
                        infoRow(tr("settings.server"), Backend.baseURL.host ?? "—")
                        Button(tr("common.signOut")) { model.signOut(); onClose() }
                            .font(T.F.small())
                            .foregroundStyle(T.S.failed)
                            .frame(minHeight: T.touchMin, alignment: .leading)

                        // 审核指南 5.1.1(v)：支持注册就必须在 App 内能删账号。
                        // 放在退出登录下面、字号更小，是因为它比退出重得多，
                        // 不该跟退出长得一样容易误点。
                        Button(tr("settings.deleteAccount")) { confirmDelete = true }
                            .font(T.F.micro())
                            .foregroundStyle(T.L.fgMuted)
                            .frame(minHeight: T.touchMin, alignment: .leading)
                    }

                    group(tr("settings.about")) {
                        infoRow(tr("settings.version"), Device.facts.appVersion)
                        infoRow("遇到问题", "hi@aiworkdeck.com")
                    }
                }
                .padding(.horizontal, T.Sp.gutter)
                .padding(.bottom, T.Sp.s16)
            }
            .background(T.L.bg)
            // 进页面拉一次用量。失败静默——占位「—」比一条报错更符合这行信息的分量
            .task { usage = try? await API.shared.mediaUsage() }
            .navigationTitle(tr("home.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("common.close"), action: onClose) }
            }
            // 不可逆，所以用 alert 而不是直接执行；文案要把「删什么、不删什么」
            // 都说全——只写「无法恢复」等于没说清代价。
            .alert(tr("settings.deleteAccount.title"), isPresented: $confirmDelete) {
                Button(tr("common.cancel"), role: .cancel) {}
                Button("注销", role: .destructive) { Task { await runDelete() } }
            } message: {
                Text(tr("settings.deleteAccount.confirm"))
            }
            .alert("注销失败", isPresented: Binding(
                get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("好", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            .overlay {
                if deleting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("正在注销")
                    }
                }
            }
        }
    }

    /// 注销成功后直接关掉设置页——账号没了，停在这一页没有意义，
    /// RootView 会因为 account 变 nil 自己回到登录页。
    private func runDelete() async {
        deleting = true
        do {
            try await model.deleteAccount()
            deleting = false
            onClose()
        } catch {
            deleting = false
            deleteError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: T.Sp.s3) {
            Eyebrow(text: title)
                .padding(.top, T.Sp.s6)
                .padding(.bottom, T.Sp.s1)
            content()
            Hairline().padding(.top, T.Sp.s2)
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(T.F.small()).foregroundStyle(T.L.fg)
            Text(v)
                .font(T.F.nano())
                .foregroundStyle(T.L.fgFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「已用 / 配额」。满了之后上传会被拒并提示去桌面端收件，这行让用户提前有数。
    private var usageCaption: String {
        guard let usage else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return "\(f.string(fromByteCount: usage.usedBytes)) / \(f.string(fromByteCount: usage.quotaBytes))"
    }

    private func requestAlbumPermission() async {
        if await AlbumSaver.ensureAuthorized() {
            albumError = nil
        } else {
            albumError = "没有相册写入权限。去「设置 → AI WorkDeck → 照片」打开，否则这个开关不会生效。"
        }
    }
}
