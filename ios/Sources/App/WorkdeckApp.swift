import SwiftUI

@main
struct WorkdeckApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // 外壳浅色。拍摄与影像浏览两个界面自己强制深色，
                // 不跟随系统 —— 那两处深色是功能性的，不是主题偏好。
                .preferredColorScheme(.light)
        }
    }
}

private struct RootView: View {
    @State private var showLibrary = false

    var body: some View {
        HomeView(
            project: DemoData.project,
            tally: DemoData.tally,
            link: DemoData.link,
            recent: DemoData.recent,
            onCapture: capture,
            onOpenLibrary: { showLibrary = true }
        )
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView(
                project: DemoData.project,
                tally: DemoData.tally,
                link: DemoData.link,
                items: DemoData.recent,
                onCapture: capture,
                onClose: { showLibrary = false }
            )
            .preferredColorScheme(.dark)
        }
    }

    private func capture() {
        // 拍摄页待建。接 AVCaptureSession，拍完立刻算 SHA-256 并写 manifest。
    }
}
