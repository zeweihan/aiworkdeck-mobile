import Foundation
import Photos

/// 存进系统相册。
///
/// **这是对「原图只留在应用沙盒」那条设计的反转，由维护者 2026-08-17 拍板。**
/// 原设计的理由是：手机丢了、相册被翻，尽调材料不该躺在相册里。
/// 现在做成开关，把这个权衡摆在设置页上让用户每次都是知情选择。
///
/// 只写入「AI WorkDeck」这个自建相册，不散落在「最近项目」里——
/// 至少让它们聚在一处，需要删的时候能一次删干净。
enum AlbumSaver {
    static let albumName = "AI WorkDeck"

    enum SaveError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: "没有相册写入权限。去「设置 → AI WorkDeck → 照片」打开。"
            case .failed(let m): m
            }
        }
    }

    /// 只申请「添加」权限（addOnly），不要读权限——
    /// 这个 App 没有任何理由读用户的相册，多要一分权限就多一分解释成本。
    static func ensureAuthorized() async -> Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if s == .authorized || s == .limited { return true }
        if s == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
        }
        return false
    }

    static func save(url: URL, kind: MediaKind) async throws {
        guard await ensureAuthorized() else { throw SaveError.denied }
        let collection = try await ensureAlbum()

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req: PHAssetChangeRequest? = kind == .photo
                    ? PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                    : PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                guard let placeholder = req?.placeholderForCreatedAsset,
                      let album = PHAssetCollectionChangeRequest(for: collection) else { return }
                album.addAssets([placeholder] as NSArray)
            }
        } catch {
            throw SaveError.failed(error.localizedDescription)
        }
    }

    private static func ensureAlbum() async throws -> PHAssetCollection {
        if let existing = findAlbum() { return existing }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            }
        } catch {
            throw SaveError.failed("无法创建相册：\(error.localizedDescription)")
        }
        guard let created = findAlbum() else {
            throw SaveError.failed("相册创建后仍找不到")
        }
        return created
    }

    private static func findAlbum() -> PHAssetCollection? {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: opts).firstObject
    }
}

/// 用户偏好。项目 id 与开关这类不是凭据，UserDefaults 足够。
enum Prefs {
    private static let albumKey = "saveToPhotoAlbum"

    /// 默认**开**：维护者明确要求影像进相册。
    /// 关掉后已经进相册的不会被移除——那是用户的相册，App 不该替他删东西。
    static var saveToAlbum: Bool {
        get {
            UserDefaults.standard.object(forKey: albumKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: albumKey) }
    }
}
