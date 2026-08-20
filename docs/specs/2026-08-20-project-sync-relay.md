# 手机端项目同步与影像中转（v1.5）实施方案

2026-08-20。修复 dev-board#30：手机端登录后「这个账号下还没有项目」。

## 根因（云端库直查取证）

1. **桌面项目从未到达云端。** iOS v1 的项目选择页调 `GET /api/projects/my`（云后端
   自己的项目表），但桌面端项目只存在于本机库；云端 project 表全库仅 1 行
   （2026-08-07 Office 插件默认项目）。没有任何机制把桌面项目清单同步上云。
2. **账号劈叉。** iOS 用了云后端本地建号的 `/api/auth/sms-login/*`（按手机号新建
   孤立账号，实测建出 user 4），而桌面/Office 插件走账户桥接（官网 accountId 映射，
   user 3）。两个身份互不相识。
3. 空态文案承诺「桌面端新建项目后回来刷新」——系统做不到。

## 架构（对 2026-08-17 设计 spec §3 的落地与偏差）

按 spec 的「云中转」形态落地：**桌面端是项目的唯一权威源，云端只做目录镜像 +
影像中转区（ACK 即删、7 天 TTL 兜底）**。本期（v1.5）明确缓做、留给 v2：

- 配对二维码与项目密钥下发（本期继续用手机号验证码登录 + 手机号认领归一账号）；
- 客户端加密（本期中转区存明文字节，落地即删仍成立）；
- TSA 证据级凭证（字段早已预留）。

### 账号归一：桥接认领手机号

- 官网 `/api/account/me`（Bearer awdk_）响应增加 `phone` 字段（11 位裸号或 null）。
- 云后端 `AwdkLoginService` 桥接成功后：若 me.phone 合法且桥接用户 `phone` 为空，
  把该号认领到桥接用户名下；若号码正被其他「手机号免密建号」用户占用，转移之
  （双方都通过短信证明过对同一手机号的控制权，是同一个人）。桥接用户已有
  **不同**手机号时不覆盖、只记日志。
- 效果：既有 iOS App 的 `sms-login`（`findOrCreateByPhone`）自然解析到桥接账号，
  **无需改登录端点、不引入官网人机验证依赖**。

### 云端新增 `/api/mobile/*`（鉴权一律 `X-Session-Id`，awdt_ 与登录会话同门）

| 端点 | 调用方 | 语义 |
|---|---|---|
| `PUT /api/mobile/projects` | 桌面 | 项目目录全量替换。体：`{deviceId, deviceName, projects:[{key,name}]}`，按 (userId, deviceId) 整批替换 |
| `GET /api/mobile/projects` | 手机 | 该账号全部设备的目录并集：`[{deviceId, key, name, deviceName}]`（裸数组，与既有 /api/projects/my 同风格） |
| `POST /api/mobile/media` | 手机 | multipart：`file` + `deviceId, projectKey, clientMediaId, fileName, mediaType, capturedAt?`。幂等键 (userId, clientMediaId)，重复上传返回既有记录 |
| `GET /api/mobile/media/status?clientMediaIds=a,b` | 手机 | `[{clientMediaId, delivered, waitingSeconds}]` |
| `GET /api/mobile/inbox?deviceId=` | 桌面 | 本设备待取件（元数据） |
| `GET /api/mobile/inbox/{id}/content` | 桌面 | 字节流 |
| `POST /api/mobile/inbox/{id}/ack` | 桌面 | 置 delivered_at + **立即删除 blob**（行保留供 status 查询，7 天清理任务删行） |

表：`mobile_project_dir(id, user_id, device_id, device_name, project_key, name, updated_at)`、
`mobile_media_inbox(id, user_id, device_id, project_key, client_media_id, file_name,
media_type, file_size, storage_path, captured_at, created_at, delivered_at)`，
唯一约束 (user_id, client_media_id)。blob 落 `{data}/mobile-relay/{userId}/{clientMediaId}`。

### 桌面端 `MobileRelayService`（随下一个桌面发版生效）

- 仅 `security.local-mode=true` 且账户已连接（`AccountService.currentKeyOrNull() != null`）时活动；云端/团队服务器天然不跑。
- 云端地址：`ai.account.base-url` 含 `workdeck.ai` → `https://addin.workdeck.ai`，否则
  `https://addin.aiworkdeck.com`；可用 `mobile.relay.base-url` 覆盖。
- 凭据：本机 awdk_ 调云端 `POST /api/auth/awdk-login` 换 awdt_，
  存 `~/.aiworkdeck/mobile-relay.json`（0600，同 account.json 规格），401 时重桥接。
- deviceId：随该文件持久化的 UUID（同一账号多台桌面机不互相踩：目录按 deviceId
  整批替换，取件按 deviceId 过滤——项目 id 是各机本地库的，跨机同 id 不同物）。
- 推目录：启动后延迟一次 + 每 10 分钟（清单哈希无变化则跳过）。
- 取件：每 60 秒轮询 inbox → 按 projectKey 解析本地项目 → 确保
  `现场影像/YYYY-MM-DD/` 目录（capturedAt 东八区日期）→ `ProjectFileService.createFile`
  + 存储服务写字节 → ACK。任一步失败：留在 inbox 下轮重试；落盘成功但 ACK 失败的
  重复取件由「目录内同名文件已存在 → 直接 ACK」挡住。

### iOS 改动

- 项目选择：`GET /api/mobile/projects`，新结构 `{deviceId, key, name}`；空态文案改为
  「桌面端用同一手机号登录并保持运行，项目约一分钟内出现在这里」。
- 上传：改 `POST /api/mobile/media` 单步 multipart（幂等键用既有 clientMediaId），
  替换两段式 create+PUT。
- 队列页：上传成功后轮询 status，「已上传」→「已抵达」（spec 不变式 4：桌面离线
  时显示已等待时长）。

## 发布顺序与生效条件

1. 官网 PR（me.phone）→ CI 自动部署两站。
2. checkba_cloud PR（云端点 + 认领 + 桌面 relay）→ 云 jar 部署北京
   addin.aiworkdeck.com（新加坡 addin.workdeck.ai 随国际版例行更新）。
   随部署做一次数据修正：把 18610211590 从孤立 user 4 移到桥接 user 3
   （与认领代码同一动作的手工前置执行）。
3. 桌面侧改动随下一个桌面发版上车（v0.21.0 修复批次已在排队）。
4. iOS PR → TestFlight 新构建。

**用户可见的完整体验 = 云部署 + 桌面新版 + TestFlight 三者齐备**；其中 1+2 完成后，
既有 App 登录即落到正确账号（能看到云端既有项目），3 完成后项目目录出现，4 完成后
拍摄归档全链路通。

## 验证

- 后端单元/集成测试（mvn，JDK 21）。
- 本地双实例全链路：server 模式 + desktop 模式两个进程，curl 驱动
  桥接→推目录→手机会话列目录→传影像→桌面取件落盘→ACK→status=delivered。
- 云部署后冒烟：未带凭据全部 401/拒绝（不是 404），目录端点空数组。
