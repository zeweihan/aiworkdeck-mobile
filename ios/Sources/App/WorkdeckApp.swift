import SwiftUI

@main
struct WorkdeckApp: App {
    @State private var model = AppModel()

    init() {
        // 锁屏卡片 / 灵动岛的「停止录音」在主进程执行，落到录音单例。
        // 顺带在启动时就把单例建起来：它的 init 会收掉上次进程遗留的 Live Activity。
        let recorder = AudioRecorderService.shared
        StopRecordingIntent.handler = { recorder.stop() }
    }

    // 词典眼下只覆盖传输状态一族，此刻切成 en 会出一半英文一半中文的界面，比全中文更糟。
    // 等取证主流程（相机、队列、图集、归档确认）文案全部入键，再在这里调 L10n.configureFromDevice()。

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.bootstrap() }
                // 内购的双通道重放（design §4）：挂上 Transaction.updates 听进程外完成的交易，
                // 再补一次 Transaction.unfinished——钱已经付了、上次没入成账的就躺在那里。
                // 两件事都放在这个 .task 里：起监听写进 App 的属性初始化式会被 SwiftUI 反复执行，
                // 起出无数个监听把主线程拖死在启动屏（见 IAP.startObservingUpdates 的注释）。
                .task {
                    IAP.startObservingUpdates()
                    await IAP.replayUnfinished()
                }
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
