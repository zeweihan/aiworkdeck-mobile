import SwiftUI

@main
struct WorkdeckApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // 外壳浅色。拍摄与影像浏览两处自己强制深色，不跟随系统——
                // 那两处的深色是功能性的，不是主题偏好。
                .preferredColorScheme(.light)
                .task { await model.bootstrap() }
        }
    }
}

private struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var route: Route?

    private enum Route: Hashable, Identifiable {
        case capture, library
        var id: Self { self }
    }

    var body: some View {
        Group {
            if !model.didRestore {
                // 恢复会话前先给一张与主界面同色的空屏，避免登录页闪一下再跳走
                Color(T.L.bg).ignoresSafeArea()
            } else if !model.isSignedIn {
                LoginView().environment(model)
            } else {
                signedIn
            }
        }
        .animation(T.A.base, value: model.isSignedIn)
    }

    private var signedIn: some View {
        HomeView(
            project: model.project,
            tally: model.tally,
            link: model.link,
            recent: model.items,
            onCapture: { route = .capture },
            onOpenLibrary: { route = .library }
        )
        .fullScreenCover(item: $route) { r in
            switch r {
            case .capture:
                CaptureView(onClose: { route = nil })
                    .environment(model)
                    .preferredColorScheme(.dark)
            case .library:
                LibraryView(
                    project: model.project,
                    tally: model.tally,
                    link: model.link,
                    items: model.items,
                    onCapture: { route = .capture },
                    onClose: { route = nil }
                )
                .preferredColorScheme(.dark)
            }
        }
    }
}
