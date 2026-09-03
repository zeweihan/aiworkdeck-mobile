import SwiftUI
import WidgetKit

/// WidgetKit 扩展入口。眼下只有录音一种 Live Activity，没有桌面小组件。
@main
struct LiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}
