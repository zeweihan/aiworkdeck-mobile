# Google Play 上架清单（国际版，`com.aiworkdeck.mobile`）

审核账号（用户名/密码/演示项目）走项目记忆 `mobile-local-verify-recipe`，不写进本文件、不入仓。

## 打包与签名

- [ ] 产物：AAB，走 **Play App Signing**——我们本地 `intl` 签名（keystore alias `aiworkdeck-intl`）
      作为「上传密钥」，Google 用它托管的应用签名密钥重新签名后分发。首次上传要在 Play Console
      「App integrity」里确认走 Play App Signing（默认新应用就是）。
- [ ] 构建命令：`./gradlew :app:bundleIntlRelease --console=plain`（详见
      `.github/workflows/android-release.yml`，或本地按 `android/README.md` 的 `local.properties` 签名配置手动跑）。
- [ ] `versionCode` 严格递增；`versionName` 走人类可读的语义版本。两者的来源与自动化见另一位并行改动
      的 `android/version.properties` 与 Gradle 覆写（本清单不重复其细节）。

## 账号与商店信息

- [ ] 开发者组织账号：已注册（任务交底确认，无需本次再办）。
- [ ] App category / content rating：需要在 Play Console 走一遍问卷（工具类 App，无 UGC 社交、
      无用户生成内容对外可见——现场影像只在账号与桌面端之间流转，不对其他用户可见）。
- [ ] Target audience and content：面向企业/专业用户（尽调、审计、验厂场景），非面向儿童；
      Target age group 选「18 and over」或「Not directed at children」对应选项。
- [ ] App access：审核员需要能登录看到完整功能——**在 Play Console 填「All functionality is
      available without special access」不成立**（需要账号+验证码），要提供演示账号说明；
      具体账号见项目记忆，不写本文件。
- [ ] Privacy policy URL：`https://www.aiworkdeck.com/en/legal/privacy`
- [ ] Data safety 表单：按 `data-safety.md` 逐项填写，标「待核」的先去核实再提交。
- [ ] Permissions 相关说明：按 `permissions.md` 末尾「Google Play Permissions declaration 填写要点」。
- [ ] 前台服务类型申报（待核）：`microphone`（录音切后台继续录，`RecordingService`）与 `dataSync`
      （上传）。需在 Play Console 应用内容 → 前台服务权限 逐类型填写用途说明（文案见 `permissions.md`），
      `microphone` 类型还要上传演示视频（录音 → 按 Home → 通知栏计时 → 回来 → 停止）。
- [ ] Account deletion 要求（Play 2023 起强制）：应用内设置页提供注销入口；是否需要额外网页入口
      见 `data-safety.md` §5，标待核。

## 商店素材

- [ ] 截图：`screenshots/phone-1080x2400/`（16:9–9:16 范围内，本仓用 1080×2400 ≈ 9:20，在 Play
      允许的最长宽高比内）与 `screenshots/phone-1080x1920/`（1080×1920 = 9:16，标准机型比例），
      两套各 7 张，数量在 Play 要求的 2–8 张范围内。上传时选一套即可（建议 1080×1920，兼容性更好），
      另一套留作以后要 9:16 之外比例时备用。
- [ ] Feature graphic：`feature-graphic-1024x500-en.png`，1024×500。
- [ ] 图标 512×512：**不在本清单产出范围**——另一位并行改动的 `android/store/icon-512.png`
      属于本任务明确排除项（避免与该文件冲突），Play Console 上传图标时用那份。
- [ ] Pre-launch report：上传 AAB 后 Play Console 自动跑，跑完看一遍是否有崩溃/无障碍警告，
      本清单不代跑，留给发布流程执行者。

## 发行范围

- [ ] Countries/regions：**排除中国大陆**（国际版走境外发行；中国大陆用户走国内版 + 国内商店，
      见 `checklist-cn-stores.md`）。
- [ ] Pricing：免费（未见付费信息，若有变化在此更新）。

## 发布前最后检查

- [ ] `node contract/tools/check.mjs` 绿（本仓契约门禁，与商店材料无直接关系但发版前照例跑）。
- [ ] 用 `apksigner`/`keytool` 核对上传产物的签名证书与预期一致（见
      `.github/workflows/android-release.yml` 的验证步骤，本地发布时手动跑同样的命令）。
