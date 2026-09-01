# 正式上架流程

三个发布面：iOS 国际版、iOS 大陆版、微信小程序。前两个走 App Store 审核，
小程序走微信公众平台审核。TestFlight / 体验版的日常发布见 `fastlane/Fastfile`
的 `beta` / `beta_cn` 与 `scripts/mp-upload.js`，这份文档只讲**正式上架**。

分工的口径：能用 API 做的都收在 `scripts/asc-listing.py`，凭据从
`fastlane/.env` 读（内容见 `5-Tech/EXTERNAL_SERVICES.md` §6）。剩下几项
Apple 没开放 API，只能在网页做，逐条列在第 3 节——那几项没做完，提审会被挡。

```bash
set -a; . fastlane/.env; set +a
.venv/bin/python scripts/asc-listing.py status intl   # 提审前体检，随时可跑
```

## 1. 两个 App 的对应关系

| | 国际版 | 大陆版 |
|---|---|---|
| flavor 参数 | `intl` | `cn` |
| Bundle ID | `com.aiworkdeck.mobile` | `com.aiworkdeck.mobile.cn` |
| ASC App ID | 6802233845 | 6803309103 |
| 发布主体 | 真善美承澤（香港，`X9B97KVA84`） | 北京京微资易（`8WKHZVR2W8`） |
| 上架区域 | 中国大陆以外 174 个区 | 仅中国大陆 |
| 文案语言 | en-US | zh-Hans |
| fastlane lane | `release` | `release_cn` |

**文案语言各只有一个，不是漏了。** App Store 的应用名在每个语言里全球唯一，
两个 App 用同一个名字「AI WorkDeck」，谁先占住某个语言，另一个再加同名的该
语言本地化就会被拒（实测报 *Cannot add localization due to app name*）。国际版
占 en-US、大陆版占 zh-Hans，各自够用，别再互相加。

## 2. 命令序列

```bash
set -a; . fastlane/.env; set +a

# 打包并上传（构建号自动取线上最大值 +1）
fastlane ios release        # 或 release_cn

# 等构建处理完（几分钟，ASC 上从 PROCESSING 变 VALID），然后挂版本
.venv/bin/python scripts/asc-listing.py attach intl <构建号>

# 文案 / 分级 / 定价 / 区域（已经跑过一遍，改了再跑）
.venv/bin/python scripts/asc-listing.py text intl
.venv/bin/python scripts/asc-listing.py rating intl
.venv/bin/python scripts/asc-listing.py price intl
.venv/bin/python scripts/asc-listing.py availability intl

# 体检 → 提审
.venv/bin/python scripts/asc-listing.py status intl
.venv/bin/python scripts/asc-listing.py submit intl --yes
```

`submit` 不加 `--yes` 只打印将要提交什么，不会真提交。

`release` / `release_cn` 与 `beta` / `beta_cn` 走的是**同一条上传通道**：ASC 里
TestFlight 与 App Store 共用同一批构建，选哪个发布是版本记录那边的事。一度改用
`upload_to_app_store`（deliver）一把梭，fastlane 2.235.0 上它在 spaceship 解析
回包时抛 `No data`（上游已知问题），而升 fastlane 会连带动到现役的 beta lane，
所以 App Store 侧全部改成直接打 REST API。

## 3. 只能在网页做的几项

Apple 没开放 API，或属于必须由人做的声明。**这几项不做完，提审必被挡。**

### 3.1 App 隐私（营养标签）

ASC →「App 隐私」→ 逐项勾。按代码实际行为，答案是：

| 数据类型 | 用途 | 是否关联身份 | 是否用于追踪 |
|---|---|---|---|
| 联系信息 → 邮箱地址 | App 功能 | 是 | 否 |
| 联系信息 → 电话号码 | App 功能 | 是 | 否 |
| 位置 → 精确位置 | App 功能 | 是 | 否 |
| 用户内容 → 照片或视频 | App 功能 | 是 | 否 |
| 用户内容 → 音频数据 | App 功能 | 是 | 否 |

依据：手机号/邮箱是登录标识；GPS 坐标与精度写进每张影像的归档信息
（`CaptureManifest`）；照片/录像/录音经中转区传到桌面端。没有广告标识符、
没有第三方分析 SDK，所以「用于追踪」一律否。

### 3.2 中国大陆 ICP 备案号（仅大陆版）

ASC → App 信息 →「App Store 法规和许可 / 中国大陆 ICP 备案号」填
`京ICP备2024096997号-13A`。会自动与工信部库比对**App 名称与主体**，
必须逐字一致——所以大陆版的应用名不能改动，保持 `AI WorkDeck`。

### 3.3 审核联系信息与演示账号

`fastlane/metadata/<flavor>/review_information/` 下有三个 `.example`，
复制成同名 `.txt` 填写（实文件已 gitignore，公开仓不收个人信息与凭据）。

两个 App 都需要：登录只有验证码一条路，而审核员既收不到中国短信，也打不开
我们的邮箱。内核仓已经加了固定验证码旁路（`config/ReviewAccountGate`，
aiworkdeck#680），服务器上按下面三步启用：

1. 注册一个审核专用账号（邮箱或手机号），**里面不要放真实数据**——那 6 位码
   是写在 ASC 审核备注里给外部人看的。邮箱那条只登录不建号，所以审核账号必须
   事先在官网注册好并验过邮箱。
2. 在 `/opt/aiworkdeck/cloud/env` 追加两行，然后重启：

   ```
   AUTH_REVIEW_ACCOUNT_IDENTITY=appreview@example.com
   AUTH_REVIEW_ACCOUNT_CODE=246813
   ```

3. 把这个账号与固定码写进 `review_information/demo_user.txt`、
   `demo_password.txt`。

审核结束后清空 `AUTH_REVIEW_ACCOUNT_IDENTITY` 即可关掉旁路。

### 3.3.1 顺带：邮箱登录开关

邮箱登录是国际版唯一能用的登录方式，但服务端默认关着（实测两站都回
「邮箱登录未启用」）。同一个 env 文件里：

```
MAIL_PASSWORDLESS_LOGIN_ENABLED=true
```

`mail.passwordless-login-enabled` 只是**其中一个**条件，还要至少一条发信通道是
开的（`MAIL_DOMESTIC_ENABLED` 走阿里云、`MAIL_GLOBAL_ENABLED` 走 Resend）——
两者缺一，`passwordlessActive()` 都是 false，报的还是同一句「邮箱登录未启用」，
从报错分不出是哪一个。审核员的邮箱多半是境外域名，所以 `MAIL_GLOBAL_ENABLED`
这条尤其要确认。

改完重启并验证：

```bash
sudo systemctl restart aiworkdeck-cloud
journalctl -u aiworkdeck-cloud -n 50 --no-pager
# 拿一个**没注册过**的地址探开关：回 code 0 说明开关已开（未注册地址后端
# 静默不发信但照常回成功，这是防账号枚举，不是发信成功）
curl -s -X POST https://addin.aiworkdeck.com/api/auth/mail-login/send-code \
  -H 'Content-Type: application/json' -d '{"email":"nobody@example.com"}'
# 再拿一个**已注册并验过邮箱**的地址试，确认真能收到信
```

### 3.4 截图

ASC → 版本 → 媒体，或用 deliver 传 `fastlane/screenshots/<flavor>/`。
尺寸要 6.9"（1320×2868，iPhone 17 Pro Max / 16 Pro Max），至少一张。

**必须用真机拍。** 模拟器里取景框是纯黑（没有摄像头）、影像库是空缩略图，
拿这种图上架既难看也不实。真机上把演示项目拍几张，再截这几屏：

- 取景首页（照片模式，有实时取景与底部 SHA-256 / GPS / 时间戳标识）
- 影像库（有内容的九宫格，能看见待传/传输中/已抵达三种状态点）
- 上传队列
- 设置页

`AppModel` 里有 `-AWDScreenshotMode` 启动参数（**只编进 Debug**），跳过登录
直接摆出 `DemoData` 的项目与统计，省得为截图去准备账号；影像本身仍需真拍。

## 4. 微信小程序 0.29.0 提审

小程序的提审与发布只能维护者在公众平台手点，`scripts/mp-upload.js` 只负责
把包传到「版本管理」。0.29.0 已上传并已设为体验版（2026-08-31）。

1. 公众平台 → 管理 → 版本管理 → 开发版本 0.29.0 →「提交审核」。
2. 填**功能页面**（最多 5 个）。当前值得报的：`pages/start/start`（扫码引流
   落地页）、拍摄页、影像库、上传队列、设置。
3. 类目要与已选服务类目一致；说明里写清「现场拍摄与归档，面向企业尽调/审计场景」。
4. **测试账号**：小程序登录走 `getPhoneNumber` 一键授权，审核员用自己的微信号
   即可完成，不需要额外账号——在补充说明里写明这一点。
5. 隐私保护指引与服务器域名在 2026-08-31 已配好（dev-board#305），提审前扫一眼没被改回去。

发布之后还有一步：dev-board#305 的 `WX_START_MINIAPP` 开关要等**正式发布版
存在**才能置 1——URL Link 对只有体验版的小程序返回 85079，体验版也不行。

## 5. 过审之后

两个 App 的版本都设成了「手动发布」（`releaseType: MANUAL`——ASC 的默认值是
`AFTER_APPROVAL`，即过审自动上架，`setversion` 会把它改掉），
过审后要人去点发布。这样能把两端与小程序凑到同一天放出去。
