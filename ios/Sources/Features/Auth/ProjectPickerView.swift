import SwiftUI

/// 选归档目标。登录后必走一次——不选项目就不知道照片该往哪去，
/// 与其让人先拍完再问，不如进门就定。
struct ProjectPickerView: View {
    @Environment(AppModel.self) private var model

    @State private var projects: [ProjectSummary] = []
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
            Eyebrow(text: "归档到")
            Text("选择项目")
                .font(T.F.display())
                .foregroundStyle(T.L.fg)
            Text("现场拍的影像会归入该项目的「现场影像 / \(AppModel.today)」。")
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
                                if let r = p.myRole {
                                    Text(roleLabel(r))
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

    private func roleLabel(_ r: String) -> String {
        switch r.uppercased() {
        case "OWNER": "我创建的"
        case "ADMIN": "管理员"
        case "MEMBER": "成员"
        case "CLIENT": "客户"
        default: r
        }
    }

    private var loadingRow: some View {
        HStack(spacing: T.Sp.s2) {
            ProgressView().controlSize(.small)
            Text("正在读取项目").font(T.F.small()).foregroundStyle(T.L.fgMuted)
        }
        .frame(minHeight: T.touchMin)
    }

    private func errorBlock(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: T.Sp.s3) {
            Text(msg).font(T.F.small()).foregroundStyle(T.S.failed)
            Button("重试") { Task { await load() } }
                .font(T.F.small())
                .foregroundStyle(T.L.accent)
        }
        .frame(minHeight: T.touchMin, alignment: .leading)
    }

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: T.Sp.s2) {
            Text("这个账号下还没有项目")
                .font(T.F.body())
                .foregroundStyle(T.L.fg)
            Text("在桌面端或网页端新建一个项目后，回到这里下拉刷新。")
                .font(T.F.micro())
                .foregroundStyle(T.L.fgFaint)
            Button("重新读取") { Task { await load() } }
                .font(T.F.small())
                .foregroundStyle(T.L.accent)
                .padding(.top, T.Sp.s2)
        }
        .frame(minHeight: T.touchMin, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            Button("退出登录") { model.signOut() }
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
