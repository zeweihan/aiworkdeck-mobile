# 小程序接真实链路（dev-board#56）实施契约

2026-08-20。把 miniprogram/ 从视觉演示壳接成真实链路。上游权威源：
`2026-08-20-project-sync-relay.md`（API）、`2026-08-17-mobile-clients-design.md`（D6 等）、
iOS 参照 `ios/Sources/Services/Backend.swift`。本文件是小程序侧的实现契约，
三块施工（基础设施 / 登录与项目页 / 首页与队列页）都以此为准，不得各自发明接口。

## 0. 红线

- 全部界面文案、注释、commit 均**不用 emoji**；不得出现「法律咨询」字样。
- 后端已全量部署在 `https://addin.aiworkdeck.com`，**不改后端**。
- 鉴权失败是 **HTTP 200 + `{"code":4010,"message":"请先登录"}`**（实测），不是 401。
- `GET /api/mobile/projects` 与 `GET /api/mobile/media/status` 成功时返回**裸数组**
  （无信封）；auth 端点返回 `{code,message,data}` 信封，code 0 才是成功。
- 视觉沿用现状：令牌单一来源 `styles/tokens.wxss`，纯白底、发丝线分区、
  字级跨度做层级、状态色只做小圆点（见设计 spec §5）。新页面照 index 页现有语汇写。

## 1. 页面与导航

app.json `pages`（顺序即入口）：

```
pages/index/index      主界面（守门人）
pages/login/login      短信登录
pages/project/project  项目选择
pages/queue/queue      传输队列
```

va/vb/vc 三个视觉方案页与 `utils/demo.ts` 删除（demo.ts 自带「接后端时整块删除」注记）。

守门逻辑在 index 的 `onShow`：无会话 → `wx.reLaunch` 到 login；有会话无选中项目 →
`wx.reLaunch` 到 project。login 成功 → reLaunch project；project 选中 → reLaunch index。
从 index 主动「切换项目」→ `wx.navigateTo` 到 project（可返回）。

`permission.scope.userLocation` 与 `requiredPrivateInfos` 从 app.json 移除：
v1 没有任何 getLocation 调用，声明未用是提审被打回项。

## 2. utils/api.ts（新建）

```ts
export const BASE_URL = 'https://addin.aiworkdeck.com'

export class ApiError extends Error { code: number }   // code：信封 code 或 -1（网络/HTTP 层）

// 会话与选中项目都走 wx.*StorageSync，键名：
//   awd.session  string        awd.user  AccountUser        awd.project  RelayProject
export function getSession(): string | null
export function setSession(v: string | null): void
export function getSelectedProject(): RelayProject | null
export function setSelectedProject(p: RelayProject | null): void

export interface AccountUser { id: number; username: string; displayName: string }
export interface LoginResult { sessionId: string; isNewUser: boolean; user: AccountUser }
export interface RelayProject { deviceId: string; deviceName: string | null; key: string; name: string }
export interface MediaStatus { clientMediaId: string; delivered: boolean; waitingSeconds: number }

export function sendLoginCode(phone: string): Promise<void>          // POST /api/auth/sms-login/send-code {phone}
export function verifyLoginCode(phone: string, code: string): Promise<LoginResult>
                                                                      // POST /api/auth/sms-login/verify；成功后自动 setSession
export function logout(): void                                        // 清 session + user + project
export function myProjects(): Promise<RelayProject[]>                 // GET /api/mobile/projects（裸数组）
export function mediaStatus(ids: string[]): Promise<MediaStatus[]>    // GET /api/mobile/media/status?clientMediaIds=a,b（裸数组）；ids 空直接返回 []
export function uploadMedia(opts: {
  filePath: string; deviceId: string; projectKey: string; clientMediaId: string;
  fileName: string; mediaType: 'image' | 'video'; capturedAt: string;   // ISO8601
  onProgress?: (percent: number) => void
}): Promise<void>                                                      // wx.uploadFile → POST /api/mobile/media，name:'file'，其余走 formData
export function uuid(): string                                         // v4，小写
```

统一响应处理（信封端点与 uploadFile 的字符串响应共用一套判读）：

1. HTTP 非 2xx → `ApiError(-1, '服务器返回 N')`。
2. 体是数组 → 成功（裸数组端点）。
3. 体是对象且有数字 `code`：0 → 成功取 `data`；**4010 → 清会话
   （setSession(null)，保留 awd.project 不动也可，登录守门会重走）+
   `wx.reLaunch('/pages/login/login')` + 抛 `ApiError(4010, '请先登录')`**；
   其他 → `ApiError(code, message || '操作失败')`。
4. 网络层失败（fail 回调）→ `ApiError(-1, '连不上服务器，检查网络后重试')`——
   与业务失败分开说（参照 iOS 注释：用户看到两种话会做完全不同的事）。

## 3. utils/queue.ts（新建）

单飞上传队列，持久化在 `wx.setStorageSync('awd.queue', QueueItem[])`。

```ts
export type QueueState = 'waiting' | 'uploading' | 'uploaded' | 'arrived' | 'failed'
export interface QueueItem {
  clientMediaId: string          // uuid()，幂等键，重传不产生重复件
  fileName: string               // 照片_20260820_141516.jpg / 录像_20260820_141516_段1.mp4
  mediaType: 'image' | 'video'
  filePath: string               // saveFile 后的沙盒路径；saveFile 失败时是临时路径
  saved: boolean
  deviceId: string; projectKey: string; projectName: string
  capturedAt: string             // ISO8601
  state: QueueState
  errorMessage?: string
  waitingSeconds?: number        // uploaded 态由 status 轮询回填
  segmentIndex?: number          // 录像分段序号，从 1 起
  createdAt: number              // Date.now()，列表排序与显示 HH:mm 用
}

export function listItems(): QueueItem[]                                   // 新→旧
export function counts(): { waiting: number; moving: number; arrived: number }
   // waiting = waiting+failed；moving = uploading+uploaded；arrived = arrived
export function enqueueCapture(tempFilePath: string, mediaType: 'image' | 'video',
                               project: RelayProject, segmentIndex?: number): QueueItem
   // 尝试 FileSystemManager.saveFile 留底（沙盒，不进相册，D4）；失败则用临时路径继续。
   // 入队后自动 processQueue()。
export function processQueue(): void          // 逐个（单飞）把 waiting → uploading → uploaded；失败 → failed
export function retry(clientMediaId: string): void        // failed → waiting + processQueue()
export function pollStatus(): Promise<boolean>            // 对 uploaded 项查 mediaStatus：
   // delivered → arrived + 删本地留底文件；未 delivered → 回填 waitingSeconds。返回是否还有未抵达项。
export function subscribe(cb: () => void): () => void     // 任何状态变化后通知；返回退订函数
```

轮询节奏由页面控制：index/queue 页 `onShow` 起 5 秒间隔调 `pollStatus()`，
`onHide/onUnload` 清定时器；没有 uploaded 项时 pollStatus 直接返回 false 不发请求。
ApiError(4010) 在 api 层已做跳登录，队列层捕获后停住即可，不重复弹窗。

## 4. 页面行为

### login（新建）

手机号（11 位，type=number）+ 验证码（type=number）两栏，「获取验证码」带 60 秒
倒计时；「登录」成功后 reLaunch 到 project。错误一律 `wx.showToast({icon:'none'})`
展示 ApiError.message。页脚固定一行小字：「登录即代表同意将拍摄影像同步至你的
AI WorkDeck 桌面端」。品牌名写法：AI WorkDeck（大写 D）。

### project（新建）

onShow 拉 `myProjects()`，按 deviceId 分组，组头显示 `deviceName || '桌面设备'`，
条目显示项目名，点选 → `setSelectedProject` → reLaunch index。
空态文案（与 iOS 同口径，spec 原文）：
「桌面端用同一手机号登录并保持运行，项目约一分钟内出现在这里」+「刷新」按钮。
支持 `onPullDownRefresh`（app.json 该页开 enablePullDownRefresh）。
页脚「退出登录」小字链接：showModal 确认 → `logout()` → reLaunch login。

### index（改造）

- 守门（见 §1）。数据全部换真：项目名/deviceName 取 `getSelectedProject()`，
  归档路径显示 `现场影像 / YYYY-MM-DD`（今天，东八区即本机时区）；
  三个统计位接 `counts()`；最近列表接 `listItems()` 前 6 条
  （kind：image→doc 图标、video→scene 图标，沿用现有图标；时间 HH:mm）。
- 原「桌面在线 · 12 秒前同步」演示行去掉，换成当前设备名 + 「切换项目」入口
  （navigateTo project）。不许再出现任何写死的演示数字。
- subscribe(queue) 驱动刷新；onShow 起轮询、onHide 停（§3）。
- 拍摄（onCapture）：`wx.chooseMedia({ count: 1, mediaType: ['image','video'],
  sourceType: ['camera'], maxDuration: 60, camera: 'back' })`。
  返回视频 → enqueueCapture(segmentIndex=1) 后进分段循环：
  `wx.showModal('已录制第 N 段（单段最长 60 秒）', '继续录制下一段吗？')`，
  确认 → 再次 chooseMedia（mediaType 只留 video）segmentIndex+1，取消 → 结束。
  返回照片 → 直接 enqueueCapture。
- D6 明示（不能默默降级）：拍摄控件下方固定小字
  「录像单段最长 60 秒，长内容自动分段归档；本端录像为记录用途，证据用途请用 iOS 端」。

### queue（重写，现在是空壳）

全量列表 + 状态文案：
waiting「待上传」/ uploading「上传中」/ failed「上传失败」+ 重试按钮 /
uploaded「已上传 · 等待桌面端接收」，waitingSeconds ≥60 时补「已等待 N 分钟」
（桌面离线不可隐瞒，spec 不变式 4）/ arrived「已抵达」。
空态：「还没有拍摄记录」。onShow 轮询、onHide 停，同 index。

## 5. 配置

- `project.config.json`：appid → `wx67b9a7d0449be0b4`；condition 列表换成
  index / login / project / queue 四页。
- 合法域名（request + uploadFile 都是 `https://addin.aiworkdeck.com`）要在
  微信公众平台后台手工配置，代码里保持 `urlCheck: false` 便于开发者工具联调。

## 6. 验证

- `npm run typecheck` 全绿（strict + noUnusedLocals）。
- 全仓 grep 无 emoji、无「法律咨询」、无残留演示数据（华创科技 / 14:22 / 148 等）。
- 开发者工具真机联调属维护者侧（需正式 appid 登录 + 合法域名生效）。
