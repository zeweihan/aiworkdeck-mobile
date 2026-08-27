import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    var onClose: () -> Void

    @State private var saveToAlbum = Prefs.saveToAlbum
    @State private var albumError: String?
    @State private var usage: API.MediaUsage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    group("影像") {
                        Toggle(isOn: $saveToAlbum) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("同时存入系统相册")
                                    .font(T.F.body())
                                    .foregroundStyle(T.L.fg)
                                // 把权衡摆在这儿，让每次选择都是知情的。
                                // 这不是吓唬人——尽调影像进相册，手机丢了或被查时
                                // 它就躺在那儿。
                                Text("拍完同时存一份到系统相册。关掉则影像只留在本应用内，手机相册里看不到。")
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

                    group("归档目标") {
                        infoRow("当前项目", model.project.name)
                        infoRow("云端中转", usageCaption)
                        Button("切换项目") { model.clearProjectSelection() }
                            .font(T.F.small())
                            .foregroundStyle(T.L.accent)
                            .frame(minHeight: T.touchMin, alignment: .leading)
                    }

                    group("账号") {
                        infoRow("已登录", model.account?.displayName ?? "—")
                        infoRow("服务器", Backend.baseURL.host ?? "—")
                        Button("退出登录") { model.signOut(); onClose() }
                            .font(T.F.small())
                            .foregroundStyle(T.S.failed)
                            .frame(minHeight: T.touchMin, alignment: .leading)
                    }

                    group("关于") {
                        infoRow("版本", Device.facts.appVersion)
                        infoRow("遇到问题", "hi@aiworkdeck.com")
                    }
                }
                .padding(.horizontal, T.Sp.gutter)
                .padding(.bottom, T.Sp.s16)
            }
            .background(T.L.bg)
            // 进页面拉一次用量。失败静默——占位「—」比一条报错更符合这行信息的分量
            .task { usage = try? await API.shared.mediaUsage() }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭", action: onClose) }
            }
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
