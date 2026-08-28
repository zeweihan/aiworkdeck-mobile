import AVFoundation
import ImageIO
import SwiftUI
import UIKit

/// 真缩略图。照片走 ImageIO 降采样，录像抽首帧，录音没有画面——
/// 保留占位色块加波形符号。加载完成前显示与旧版一致的占位渐变，
/// 所以任何调用点都不会出现空白闪烁。
struct EvidenceThumb: View {
    let item: CaptureItem
    var onDark: Bool = false

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            ThumbPlaceholder(kind: item.kind, onDark: onDark)

            if let image {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else if item.kind == .audio {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(onDark ? Color.white.opacity(0.4) : T.L.fgFaint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
        .task(id: item.id) {
            guard item.kind != .audio, image == nil else { return }
            image = await ThumbLoader.shared.thumbnail(
                id: item.id, url: item.localURL, kind: item.kind,
                maxPixel: 320 * displayScale
            )
        }
    }
}

/// 缩略图加载器。全尺寸 JPEG 直接进内存会在网格里爆掉，
/// 所以照片必须走 CGImageSource 的降采样路径，录像抽帧也限制最大边。
actor ThumbLoader {
    static let shared = ThumbLoader()

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 240
    }

    func thumbnail(id: UUID, url: URL, kind: MediaKind, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(id.uuidString)-\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let img: UIImage? = switch kind {
        case .photo: photoThumb(url: url, maxPixel: maxPixel)
        case .video: await videoThumb(url: url, maxPixel: maxPixel)
        case .audio: nil
        }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }

    private func photoThumb(url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    private func videoThumb(url: URL, maxPixel: CGFloat) async -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        // 取 0.1 秒处而不是 0：部分编码的首帧是纯黑的
        let t = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? await gen.image(at: t).image else { return nil }
        return UIImage(cgImage: cg)
    }
}
