import SwiftUI

/// 选归档目标。登录后必走一次——不选项目就不知道照片该往哪去，
/// 与其让人先拍完再问，不如进门就定。
struct ProjectPickerView: View {
    @Environment(AppModel.self) private var model

    @State private var projects: [RelayProject] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if loading {
                loadingRow
            } else if let error {
                errorBlock(error)
            } else if projects.isEmpty {
                emptyBlock
            } else {
                list
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, T.Sp.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(T.L.bg)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: T.Sp.s2) {
            Eyebrow(text: tr("project.eyebrow"))
            Text(tr("project.title"))
                .font(T.F.display())
                .foregroundStyle(T.L.fg)
            Text(tr("project.hint", ["date": AppModel.today]))
                .font(T.F.micro())
                .foregroundStyle(T.L.fgFaint)
                .padding(.top, T.Sp.s1)
        }
        .padding(.top, T.Sp.s10)
        .padding(.bottom, T.Sp.s6)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(projects) { p in
                    Button {
                        Task { await model.selectProject(p) }
                    } label: {
                        HStack(spacing: T.Sp.s3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                    .font(T.F.body())
                                    .foregroundStyle(T.L.fg)
                                    .lineLimit(1)
                                if let d = p.deviceName, !d.isEmpty {
                                    Text(d)
                                        .font(T.F.nano())
                                        .foregroundStyle(T.L.fgFaint)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(T.L.fgFaint)
                        }
                        .frame(minHeight: T.touchMin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: T.Sp.s2) {
            ProgressView().controlSize(.small)
            Text(tr("project.loading")).font(T.F.small()).foregroundStyle(T.L.fgMuted)
        }
        .frame(minHeight: T.touchMin)
    }

    private func errorBlock(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: T.Sp.s3) {
            Text(msg).font(T.F.small()).foregroundStyle(T.S.failed)
            Button(tr("project.retry")) { Task { await load() } }
                .font(T.F.small())
                .foregroundStyle(T.L.accent)
        }
        .frame(minHeight: T.touchMin, alignment: .leading)
    }

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: T.Sp.s2) {
            Text(tr("project.emptyTitle"))
                .font(T.F.body())
                .foregroundStyle(T.L.fg)
            // 说实话：列表来自桌面端的自动同步，前提是桌面端开着且登录同一手机号。
            // 不要写「新建项目后刷新」——不满足前提时那句话怎么做都不会应验。
            Text("在电脑上用同一手机号登录 AI WorkDeck 并保持运行，项目会在一分钟内出现在这里。")
                .font(T.F.micro())
                .foregroundStyle(T.L.fgFaint)
            Button(tr("project.reload")) { Task { await load() } }
                .font(T.F.small())
                .foregroundStyle(T.L.accent)
                .padding(.top, T.Sp.s2)
        }
        .frame(minHeight: T.touchMin, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            Button(tr("common.signOut")) { model.signOut() }
                .font(T.F.small())
                .foregroundStyle(T.L.fgMuted)
                .frame(minHeight: T.touchMin)
        }
        .padding(.bottom, T.Sp.s4)
    }

    private func load() async {
        loading = true; error = nil
        do {
            projects = try await API.shared.myProjects()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
