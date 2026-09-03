import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo as fs, fileUri } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { CaptureItem, MediaKind, MediaKindOps } from '../model/Capture'
import { uploadFileName } from '../model/UploadNaming'
import { ServiceLocator } from './ServiceLocator'

const DOMAIN: number = 0x0000
const TAG: string = 'AlbumSaver'

/**
 * 存进系统相册。**这是「原件只留在应用沙盒」那条默认的反转**，由 `Prefs.saveToAlbum` 开关控制
 * （默认关，spec H8），与 iOS / 安卓同一权衡：手机丢了、相册被翻，尽调材料不该躺在相册里，
 * 所以要用户知情选择。
 *
 * 录音不进相册：现场录音不属于音乐库（三端一致）。
 *
 * 鸿蒙没有静默写相册的路——`ohos.permission.WRITE_IMAGEVIDEO` 是受限权限，要 AGC 批 ACL。
 * 未获批之前只能走 `showAssetsCreationDialog`（`@ohos.file.photoAccessHelper.d.ts:2548`）：
 * 系统弹一次确认，用户点了才给一个可写的目标 uri，再把原件拷进去。所以这条链是**每件一弹窗**，
 * 也正是设置页要提前说清楚的那句话。
 */
export class AlbumSaver {
  /**
   * 开关开着才存。失败与用户取消都只记日志——相册是派生副本，库里那份原件才是唯一可信的一份，
   * 存不进去不该影响取证链。
   */
  async saveIfEnabled(item: CaptureItem): Promise<void> {
    if (item.kind === MediaKind.audio) return
    let enabled: boolean = false
    try {
      enabled = await ServiceLocator.prefs.saveToAlbum()
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'read saveToAlbum failed: %{public}s', `${e}`)
      return
    }
    if (!enabled) return

    const ext: string = MediaKindOps.ext(item.kind)
    const name: string = uploadFileName(item.kind, item.capturedAtMs(), item.manifest.clientMediaId)
    const config: photoAccessHelper.PhotoCreationConfig = {
      title: name.substring(0, name.length - ext.length - 1),
      fileNameExtension: ext,
      photoType: item.kind === MediaKind.video
        ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE,
    }
    try {
      const helper: photoAccessHelper.PhotoAccessHelper =
        photoAccessHelper.getPhotoAccessHelper(ServiceLocator.ctx)   // d.ts:48
      // uri 不能自己拼，得由系统给（d.ts:2540 的 NOTE）；沙盒文件用 fileUri.getUriFromPath
      const srcUri: string = fileUri.getUriFromPath(item.localPath)  // @ohos.file.fileuri.d.ts:162
      const targets: string[] = await helper.showAssetsCreationDialog([srcUri], [config])
      if (targets.length === 0) {
        hilog.info(DOMAIN, TAG, '%{public}s', 'user declined saving to album')
        return
      }
      copyInto(targets[0], item.localPath)
      await ServiceLocator.store.markSavedToAlbum(item.id)
      hilog.info(DOMAIN, TAG, '%{public}s', 'saved to album')
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'save to album failed: %{public}s', `${e}`)
    }
  }
}

/** 返回的目标 uri 带写权限，打开它拿 fd 再让系统拷字节，不把整个文件读进内存。 */
function copyInto(targetUri: string, srcPath: string): void {
  const dst: fs.File = fs.openSync(targetUri, fs.OpenMode.WRITE_ONLY)
  try {
    fs.copyFileSync(srcPath, dst.fd)   // @ohos.file.fs.d.ts:855
  } finally {
    fs.closeSync(dst)
  }
}
