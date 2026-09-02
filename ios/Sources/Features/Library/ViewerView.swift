import AVKit
import SwiftUI

/// 全屏看大图。深色底，左右滑切换同一天的其他件；照片可缩放，录像/录音走系统播放器。
/// 顶部只放核对要用的三样：时间、状态、哈希前缀。不做编辑、不做分享——取证件不该从这里流出去。
struct ViewerView: View {
    let items: [CaptureItem]
    @State var index: Int
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    page(item).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            topBar
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func page(_ item: CaptureItem) -> some View {
        switch item.kind {
        case .photo:
            ZoomablePhoto(item: item)
        case .video, .audio:
            MediaPlayerPage(item: item)
        }
    }

    private var topBar: some View {
        let item = items[min(max(index, 0), items.count - 1)]
        return HStack(spacing: T.Sp.s3) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: T.touchMin, height: T.touchMin)
            }
            .accessibilityLabel(tr("common.close"))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: T.Sp.s1) {
                    StatusDot(state: item.state, size: 5, onDark: true)
                    Text(item.state.caption)
                        .font(T.F.small())
                        .foregroundStyle(.white)
                    Text(RelativeTime.clock(item.capturedAt))
                        .font(T.F.mono(11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(item.manifest.sha256.prefix(12))
                    .font(T.F.mono(10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            Text("\(index + 1) / \(items.count)")
                .font(T.F.mono(11))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.trailing, T.Sp.s3)
        }
        .padding(.leading, T.Sp.s2)
        .padding(.bottom, T.Sp.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// 照片页：双指缩放、双击 1x / 2.5x 切换、放大后可拖。
/// 图按 2048pt 降采样：全尺寸 JPEG 进内存在连续左右滑时会被系统杀掉。
private struct ZoomablePhoto: View {
    let item: CaptureItem

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnify.simultaneously(with: drag))
                        .onTapGesture(count: 2) { toggleZoom() }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: item.id) {
            image = await ThumbLoader.shared.thumbnail(
                id: item.id, url: item.localURL, kind: .photo,
                maxPixel: 2048 * displayScale
            )
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                scale = min(max(lastScale * v.magnification, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 { reset() }
            }
    }

    /// 只在放大后接管拖动，否则会抢掉 TabView 的翻页手势
    private var drag: some Gesture {
        DragGesture(minimumDistance: scale > 1 ? 0 : 1000)
            .onChanged { v in
                offset = CGSize(width: lastOffset.width + v.translation.width,
                                height: lastOffset.height + v.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(T.A.base) {
            if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
        }
    }

    private func reset() {
        scale = 1; lastScale = 1
        offset = .zero; lastOffset = .zero
    }
}

/// 录像与录音都交给系统播放器：录音没有画面，播放器本身就是界面，再叠一个波形符号说明这是声音。
private struct MediaPlayerPage: View {
    let item: CaptureItem
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            if item.kind == .audio {
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                    .allowsHitTesting(false)
            }
        }
        .onAppear { player = AVPlayer(url: item.localURL) }
        .onDisappear { player?.pause(); player = nil }
    }
}
