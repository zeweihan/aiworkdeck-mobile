# 图集按项目分组 + 传输三态 + 图集工具（iOS 与小程序）

dev-board：#383（iOS 影像绑定项目）、#384（三态改名与按项目计数）、
#385（图集分项目分日期）、#386（图集工具：大小 / 视图 / 删除）。

用户 2026-09-02 反馈：切换了项目，图集里的照片仍顺序混排，不分项目、不分日期；
不能选大小、切视图、删除；上传进度也不跟着项目走。三个进度状态「待传 / 传输中 /
已上传」不科学。

## 用户拍板的四条

1. 状态桶改为「上传中 / 已暂存 / 已落盘」；失败件留在「上传中」桶内，保留红点与原因，
   桶计数有失败时附「含 N 条失败」。
2. 图集默认只看当前项目，顶部可切换看其他项目；项目内按日期分段。
3. 删除本地原图任何状态都允许（上传中的强警告）。
4. 小程序「已抵达后自动删本地留底」改为不自动删，与 iOS 对齐。

## 1. iOS 影像绑定项目（#383）

现状：`CaptureItem` / manifest 没有项目字段，`UploadQueue.kick()` 用「当前选中项目」
上传所有 waiting 件。切项目后，原项目未传完的照片会传进新项目。这是取证材料归档错位。
小程序 `QueueItem` 已有 `deviceId / projectKey / projectName`，不受影响。

改法：

- `StoredRow` 与 `CaptureItem` 增加 `project: RelayProject?`（RelayProject 已是 Codable）。
  旧记录解码为 nil。
- `EvidenceStore.save(...)` 增加 `project:` 参数；`AppModel.store` 传 `selectedProject`。
- `UploadQueue.kick()` 逐件用 `item.project` 作为上传目标。
  旧记录 `project == nil` 时沿用当前项目，**并把它写回 manifest**——照片实际去了哪里必须
  留痕。当前项目也为 nil 时跳过这一件（保持 waiting）。
- `AppModel.clearProjectSelection` 注释改成事实：已拍影像各自记着项目，切项目不影响它们的去向。

分组标识用 `RelayProject.id`（`deviceId:key`）。旧记录 nil 归入「未知项目」，只在有记录时出现。

## 2. 传输三态（#384）

**内部五态状态机不变**（waiting / moving / uploaded / arrived / failed）——它是存储契约、
队列逻辑与后端回执的基础。改的是**展示层**：新增 `TransferPhase`（iOS）/ `Phase`（TS）
三段，映射固定：

| 内部状态 | 阶段 | 单件文案 | 点色 |
|---|---|---|---|
| waiting / moving | 上传中 | 上传中 | 橙（S.waiting） |
| failed | 上传中 | 上传失败 | 红（S.failed） |
| uploaded | 已暂存 | 已暂存 · 等电脑取回 | 蓝（S.moving） |
| arrived | 已落盘 | 已落盘 | 绿（S.arrived） |

令牌名（waiting / moving / arrived）不改，只改语义注释；`scripts/check-tokens.mjs`
的两端对拍不受影响。

计数：`TransferTally { uploading, failed, staged, landed }`，`failed ⊆ uploading`。
展示「N 上传中（含 M 失败）/ N 已暂存 / N 已落盘」，M 为 0 时不显示括号。
**计数只数当前项目**（首页顶部、图集顶栏、首页右下「本项目」总数）。

队列页（iOS QueueView / 小程序 queue 页）：只列当前项目，分区「失败 · 需要处理 /
上传中 / 已暂存 · 等电脑取回 / 已落盘」；末尾一行小字「其他项目还有 N 件未落盘」
（N > 0 时才显示），避免别的项目的失败件被完全藏起来。

## 3. 图集分项目分日期（#385）

### iOS（重做 LibraryView）

- 输入全部 items；内部状态 `viewing: ProjectKey?`，默认当前项目。
- 顶栏项目名变成菜单：列出「当前项目」以及所有**有记录的**项目（含「未知项目」），
  选中即切换 `viewing`。只切看的对象，不切拍摄目标。
- 项目内按自然日分段（本机时区），段头「M月d日 · N 件」，用 `LazyVGrid` 的 `Section`
  + `pinnedViews: [.sectionHeaders]`。段内按拍摄时间倒序。
- 顶栏计数行按 `viewing` 项目计算。

### 小程序（新建 `pages/gallery/gallery`）

- 深色（D7：影像浏览走深色），语汇照 index 页的 `--dk-*` 令牌。
- 首页左下最近缩略图入口改为进图集；顶部三个计数仍进队列页。
- 顶栏标题 = 正在看的项目名，点标题 `wx.showActionSheet` 列出有记录的项目切换。
- 按自然日分段，段头「M月d日 · N 件」；段内网格。
- `queue.ts` 增加纯查询 `listItems({ project })` 过滤，不动状态机。

## 4. 图集工具（#386）

两端一致：

- **列数**：2 / 3 / 4 列循环切换，顶栏一个按钮，持久化
  （iOS UserDefaults `libraryColumns`；小程序 storage `awd.gallery.cols`）。
- **视图**：网格 / 列表切换，持久化（`libraryViewMode` / `awd.gallery.view`）。
  列表行 = 缩略图 + 状态文案 + 时间 + 失败原因 + 哈希前 12 位（小程序无哈希，显示文件名）。
- **删除**：顶栏「选择」进入多选；单元格点选打勾；底部「删除 N 件」。
  删除 = 删本地原图 + 删记录（记录留着而图没了，图集里会出现永远打不开的空格，
  比直接消失更糟）。确认文案按所选中**最坏的阶段**给：
  - 全是已落盘：「删除 N 件本地原图？电脑上已有副本。」
  - 含已暂存：「其中 N 件电脑还没取回。中转区 7 天后清理，电脑若未及时接收，
    这些影像将无法找回。」
  - 含上传中 / 失败：「其中 N 件还没送出去。删了就没了，无法找回。」
  确认按钮红色「删除」。
- iOS `EvidenceStore.delete(ids:)`：删 media + manifest。正在上传的件被删，
  上传完成后的 `updateState` 找不到 manifest 会静默返回，已是现有行为。
- 小程序 `queue.ts` 增加 `removeItems(ids)`：从 storage 移除，`saved` 的顺手
  `removeSavedFile`。`pollStatus` 里 delivered 后的自动 `removeSavedFile` 删掉（拍板 4）。

不做：全屏看大图（两端都没有，另开卡）；按项目以外的维度筛选。

## 5. 验证

- 纯逻辑单测：阶段映射、按项目计数、按日分组、删除文案选择。
  iOS 加 `WorkdeckTests` 单测 target（XcodeGen），小程序在 `tests/` 用 `node --test`
  跑无 wx 依赖的纯模块（Node 22 原生 strip-types）。
- `npm run typecheck` 过；`xcodegen generate` 后 Debug 构建过；模拟器跑通：
  切项目拍照 → 图集只见当前项目 → 切换看另一项目 → 三态计数对 → 多选删除。
