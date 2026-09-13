package com.aiworkdeck.mobile

import com.aiworkdeck.mobile.model.RelayProject
import com.aiworkdeck.mobile.services.AccountUser
import com.aiworkdeck.mobile.services.Loc
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime

/**
 * 上架截图模式。对位 iOS 的启动参数 `-AWDScreenshotMode` 与鸿蒙的 `--ps awdShots 1`：
 *
 *   adb shell am start -n <pkg>/com.aiworkdeck.mobile.MainActivity --ez awdScreenshot true
 *
 * **只在 debug 构建里成立**——[configure] 第一行看 `BuildConfig.DEBUG`，release 包里
 * [enabled] 永远是 false，这套假状态进不了发行二进制。
 *
 * 它只解决模拟器上截不出图的三件事，别的一概不碰：
 * 1. 没有服务端会话也能进主界面（截图不该依赖一个会过期的审核账号）；
 * 2. 模拟器没有相机与 GPS——取景区改用一张静态现场照，定位给一个固定精度；
 * 3. 选项目页的列表来自桌面端上报，截图机器上没有桌面端，这里直接给三条演示项目。
 *
 * 影像本身不在这里造：图集/队列/查看器读的是应用私有目录里的 manifest 与原件，
 * 由 `scripts/store-shots/capture-android.sh` 用 `run-as` 灌进去（安卓能从主机写沙盒，
 * 不必像鸿蒙那样把种子图打进包里）。
 */
object ScreenshotMode {
    /** `am start --ez awdScreenshot true` 的 extra 名。 */
    const val EXTRA: String = "awdScreenshot"

    /** `--es awdScreen queue` 的 extra 名。直接落到某一屏，免得靠坐标点。 */
    const val EXTRA_SCREEN: String = "awdScreen"

    /** 要落到哪一屏：null / "home" / "queue" / "library" / "viewer" / "settings"。 */
    var screen: String? = null
        private set

    /** 静态取景图的固定落点，capture 脚本每屏换一张。 */
    const val STAGE_FILE: String = "screenshot-stage.jpg"

    var enabled: Boolean = false
        private set

    /** 取景区要贴的那张现场照；脚本没灌图时为 null，界面退回原来的相机预览。 */
    var stage: File? = null
        private set

    /**
     * 归档日期。界面上那行归档路径本来取「今天」，截图要的是规格里固定的 2026-09-12
     * （种子件的拍摄日期也是这天）——拨模拟器的系统时钟会把 system_server 拽 ANR，
     * 不如在这里给一个定值，哪天重跑都截得出同一张。
     */
    const val ARCHIVE_DATE: String = "2026-09-12"

    /** 固定定位：上海人民广场附近，精度 5 米（§2 第 1 屏要「±5 米」）。 */
    val loc: Loc = Loc(31.23041, 121.47370, 5.0)

    val account: AccountUser = AccountUser(id = 1, username = "demo", displayName = "演示账号")

    /** 选项目页的三条演示项目，名称取自 `docs/specs/2026-09-13-store-assets-design.md` §3。 */
    val projects: List<RelayProject> = listOf(
        RelayProject(deviceId = "dev-shots", deviceName = "MacBook Pro", key = "p-1", name = "华创科技 A 轮尽调"),
        RelayProject(deviceId = "dev-shots", deviceName = "MacBook Pro", key = "p-2", name = "恒达制造 验厂"),
        RelayProject(deviceId = "dev-shots", deviceName = "MacBook Pro", key = "p-3", name = "南山路 12 号 工程验收"),
    )

    /** 水印那行时刻：对齐最后一件种子的拍摄时间，免得画面上一半 09-12 一半今天。 */
    private val STAMP: Instant = OffsetDateTime.parse("${ARCHIVE_DATE}T15:16:49+08:00").toInstant()

    fun stamp(now: Instant): Instant = if (enabled) STAMP else now

    /** 归档路径与选项目页提示上的日期：截图模式给定值，平时还是今天。 */
    fun archiveDate(): String = if (enabled) ARCHIVE_DATE else LocalDate.now().toString()

    fun configure(on: Boolean, screen: String?, filesDir: File) {
        if (!BuildConfig.DEBUG || !on) return
        enabled = true
        this.screen = screen
        stage = File(filesDir, STAGE_FILE).takeIf { it.exists() }
    }
}
