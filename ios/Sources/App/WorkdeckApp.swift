import SwiftUI

@main
struct WorkdeckApp: App {
    @State private var model = AppModel()

    init() {
        // 大陆版 bundle id 以 .cn 结尾，永远中文；国际版跟随设备语言。
        // WorkdeckTests 是 hosted 单测（宿主是本 App），跑测试时这段 init 真的会执行一遍——
        // 测试要确定性，不能跟着模拟器当时的系统语言摇摆，所以测试进程里跳过设备语言探测。
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !underTest, Bundle.main.bundleIdentifier?.hasSuffix(".cn") == false {
            L10n.configureFromDevice()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.bootstrap() }
        }
    }
}

private struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var route: Route?

    private enum Route: Hashable, Identifiable {
        case library, queue, settings
        var id: Self { self }
    }

    var body: some View {
        Group {
            if !model.didRestore {
                // 恢复会话前先给一张与主界面同色的空屏，避免登录页闪一下再跳走
                Color(T.L.bg).ignoresSafeArea()
            } else if !model.isSignedIn {
                // 外壳浅色。取景首页与影像浏览自己强制深色，不跟随系统——
                // 那两处的深色是功能性的，不是主题偏好。
                LoginView().environment(model)
                    .preferredColorScheme(.light)
            } else if model.selectedProject == nil {
                // 不选项目就不知道照片往哪去。与其让人先拍完再问，不如进门就定。
                ProjectPickerView().environment(model)
                    .preferredColorScheme(.light)
            } else {
                signedIn
            }
        }
        .animation(T.A.base, value: model.isSignedIn)
        .animation(T.A.base, value: model.selectedProject)
    }

    private var signedIn: some View {
        HomeView(
            paused: route != nil,
            onOpenLibrary: { route = .library },
            onOpenQueue: { route = .queue },
            onOpenSettings: { route = .settings }
        )
        .environment(model)
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $route) { r in
            switch r {
            case .queue:
                QueueView(onClose: { route = nil }).environment(model)
                    .preferredColorScheme(.light)
            case .settings:
                SettingsView(onClose: { route = nil }).environment(model)
                    .preferredColorScheme(.light)
            case .library:
                LibraryView(onClose: { route = nil })
                    .environment(model)
                    .preferredColorScheme(.dark)
            }
        }
    }
}
