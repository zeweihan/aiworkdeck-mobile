# 国内应用商店上架清单（国内版，`com.aiworkdeck.mobile.cn`）

覆盖华为 AGC、应用宝（腾讯）、小米、OPPO、vivo、荣耀等主流国内安卓商店的共同材料与已确认的
个别差异。不确定的条目标「待核」，不要替商店后台的实际要求编答案——上架前逐条对照各商店最新的
开发者文档确认一遍。

## 共同材料

- [ ] **APK**：用国内 `cn` 签名（keystore alias `aiworkdeck-cn`）签名，走
      `./gradlew :app:assembleCnRelease --console=plain`（国内商店大多直接收 APK，不像 Play 要 AAB）。
- [ ] **软著**（计算机软件著作权登记证书）：**待核**——交底事实未提供是否已办理/证书号，
      上架前需确认软著状态，多数国内商店（尤其华为、应用宝）要求提交。
- [ ] **ICP 备案号**：京ICP备2024096997号-13A。**需要办理「新增安卓 App 平台」的备案变更**
      （现有备案号大概率是网站/既有客户端的，新增一个安卓包名/应用通常要在工信部备案系统里
      给该 ICP 备案号追加或核验安卓平台信息，具体流程按各省通信管理局要求，标待核）。
- [ ] **隐私政策 URL**：`https://www.aiworkdeck.com/zh/legal/privacy`
- [ ] **权限用途说明**：直接用 `permissions.md` 里「国内商店权限用途说明」那一段。
- [ ] **截图**：`screenshots/phone-1080x1920/`，5 张起（本仓已备 7 张：home / library / viewer /
      queue / settings / projects / login，商店要求 5 张时按顺序取前 5 张，home 系列在前）。
- [ ] **图标 512×512**：**不在本清单产出范围**——`android/store/icon-512.png` 由另一位并行改动
      的任务负责，本任务明确排除，避免文件冲突。
- [ ] **应用介绍 / 更新说明**：`listing/zh-Hans/full_description.txt` /
      `listing/zh-Hans/release_notes.txt`，字段映射见 `listing/README.md`。
- [ ] **应用名称 / 一句话简介**：`listing/zh-Hans/title.txt` / `listing/zh-Hans/short_description.txt`。
- [ ] **联系人 / 客服信息**：**待核**——交底事实未提供上架联系人姓名、电话或客服邮箱，多数商店
      开发者后台要求填写真实联系人信息，需要另行核实提供。
- [ ] **权限弹窗与隐私政策一致性**：`permissions.md` 表格里的措辞已对齐 `AndroidManifest.xml`
      与实际请求时机，各商店审核若逐条比对权限弹窗文案与隐私政策，以这份表格为准。

## 各商店已确认的差异点

- **华为 AGC（AppGallery Connect）**：审核明确要求隐私政策文本与应用内权限弹窗描述保持一致
      （不能隐私政策写一套、弹窗另一套）——本仓 `permissions.md` 与隐私政策措辞均已对齐 iOS
      purpose string，上架前建议把隐私政策页面文本与 `permissions.md` 表格再对一遍。
- **应用宝（腾讯）**：支持「微下载」（免安装直接体验），是否要为这个应用单独适配/申请微下载，
      **待核**——交底事实只提到这是应用宝的一个特性，未说明本应用是否需要/适合接入。
- **小米 / OPPO / vivo / 荣耀（金标联盟，即 Android 应用市场联合审核联盟）**：对 `targetSdk`
      有最低版本要求（金标联盟每年会跟随 Android 大版本上调门槛）。本仓当前
      `android/app/build.gradle.kts` 里 `targetSdk = 37`，**待核**——需要在提交前核对联盟当时
      公布的最新最低 targetSdk 要求数字（该数字会随时间变化，不要在本清单里写死一个可能过期的值）。

## 发行范围

- 国内六家商店仅面向中国大陆用户；国际版（`com.aiworkdeck.mobile`）走 Google Play 且排除中国大陆，
  两边渠道互不重叠，见 `checklist-google-play.md`。

## 发布前最后检查

- [ ] `node contract/tools/check.mjs` 绿。
- [ ] 用 `apksigner verify --print-certs` 核对上传 APK 的证书与 `aiworkdeck-cn` 一致（见
      `.github/workflows/android-release.yml` 的校验步骤）。
