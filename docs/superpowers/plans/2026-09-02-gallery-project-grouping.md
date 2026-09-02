# 图集按项目分组 + 传输三态 + 图集工具 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS 影像绑定项目（修归档错位），两端把传输状态展示改为「上传中 / 已暂存 / 已落盘」并按项目计数，图集按项目分组、按日分段，并提供列数、视图切换和多选删除。

**Architecture:** 内部五态状态机（waiting/moving/uploaded/arrived/failed）与存储契约不动；新增展示层「阶段」映射与纯分组函数（iOS `LibraryGrouping`，小程序 `utils/phase.ts`），所有页面从这一层派生文案、计数、分组。iOS 记录增加 `project` 字段并让上传按件内项目走。

**Tech Stack:** Swift 5.9 / SwiftUI（XcodeGen 生成工程，iOS 17+）；微信小程序原生 TS（`tsc --noEmit` 类型检查）；单测：XCTest（新增 `WorkdeckTests` target）、Node 22 `node --test`（原生 strip-types）。

**Spec:** `docs/specs/2026-09-02-gallery-project-grouping-design.md`

## Global Constraints

- 三个阶段文案固定：「上传中」「已暂存」「已落盘」；失败件文案「上传失败」，留在「上传中」桶内；桶计数有失败时附「含 N 失败」。
- 内部状态枚举（iOS `TransferState`、TS `QueueState`）及其字符串值不改；`awd.queue` 存储契约只增不改。
- 令牌名 `waiting / moving / arrived / failed` 不改（`scripts/check-tokens.mjs` 对拍）。点色映射：waiting/moving → waiting 色；failed → failed 色；uploaded → moving 色；arrived → arrived 色。
- 删除 = 删本地原图 + 删记录。确认文案按所选中最坏阶段：全部已落盘 →「删除 N 件本地原图？电脑上已有副本。」；含已暂存 →「其中 N 件电脑还没取回。中转区 7 天后清理，电脑若未及时接收，这些影像将无法找回。」；含上传中/失败 →「其中 N 件还没送出去。删了就没了，无法找回。」
- 图集默认看当前项目；项目标识 = `deviceId:key`（iOS `RelayProject.id`）；iOS 旧记录无项目 → id `"unknown"`、名「未知项目」。
- 列数 2/3/4，默认 3；视图 grid/list，默认 grid。持久化键：iOS `libraryColumns` / `libraryViewMode`；小程序 `awd.gallery.cols` / `awd.gallery.view`。
- 小程序 `pollStatus` 抵达后**不再**自动 `removeSavedFile`。
- 提交信息末尾加 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`。
- iOS 工程：`ios/Workdeck.xcodeproj` 由 `xcodegen generate --spec ios/project.yml --project ios` 生成（gitignored）；**不要碰**仓库里那份 `ios/Workdeck 2.xcodeproj`。
- 构建/测试命令（模拟器 iPhone 17 Pro Max 已启动）：
  - 生成：`cd ios && xcodegen generate`
  - 单测：`xcodebuild test -project ios/Workdeck.xcodeproj -scheme Workdeck -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:WorkdeckTests CODE_SIGNING_ALLOWED=NO`
  - 小程序：`npm run typecheck`、`npm test`

---

## 文件结构

**iOS**
- `ios/project.yml` — 加 `WorkdeckTests` target 与 scheme testTargets
- `ios/Sources/Model/CaptureItem.swift` — `TransferPhase`、新 `TransferTally`、`CaptureItem.project`、`projectID`
- `ios/Sources/Model/LibraryGrouping.swift`（新）— 纯函数：项目列表、按项目筛选、按日分段、删除文案
- `ios/Sources/Services/EvidenceStore.swift` — `save(project:)`、`setProject`、`delete(ids:)`、去掉 `tally()`
- `ios/Sources/Services/UploadQueue.swift` — 按件内项目上传
- `ios/Sources/App/AppModel.swift` — `currentItems`、`tally` 计算属性、`delete(ids:)`、`store` 传项目
- `ios/Sources/App/DemoData.swift` — 适配新类型
- `ios/Sources/Design/Components.swift` — `StatusDot` 点色映射
- `ios/Sources/Features/Home/HomeView.swift` — 三态计数行、本项目总数、最近影像取当前项目
- `ios/Sources/Features/Queue/QueueView.swift` — 只列当前项目、四分区、其他项目提示
- `ios/Sources/Features/Library/LibraryView.swift` — 重做：项目切换、按日分段、列数/视图/多选删除
- `ios/Sources/App/WorkdeckApp.swift` — `LibraryView(onClose:)` 新签名
- `ios/Tests/LibraryGroupingTests.swift`（新）、`ios/Tests/TransferPhaseTests.swift`（新）

**小程序**
- `package.json` — 加 `"test": "node --test tests/"`
- `miniprogram/utils/phase.ts`（新）— 纯函数：阶段、文案、点类、计数、项目 id、按日分段、删除文案、项目列表
- `tests/phase.test.ts`（新）
- `miniprogram/utils/queue.ts` — `QueueState` 改从 phase 导入并 re-export；`listItems(projectId?)`、`tallyFor(projectId)`、`otherPendingCount(projectId)`、`removeItems(ids)`；`pollStatus` 去掉自动删文件
- `miniprogram/pages/index/index.ts|wxml|wxss` — 三态标签、按项目计数、最近入口进图集
- `miniprogram/pages/queue/queue.ts|wxml|wxss` — 只列当前项目、分区、其他项目提示、文案走 phase
- `miniprogram/pages/gallery/gallery.ts|wxml|wxss|json`（新）— 图集页
- `miniprogram/app.json` — 注册 gallery 页

---

### Task 1: iOS 单测 target 与阶段映射

**Files:**
- Modify: `ios/project.yml`
- Modify: `ios/Sources/Model/CaptureItem.swift`
- Create: `ios/Tests/TransferPhaseTests.swift`

**Interfaces:**
- Produces: `enum TransferPhase { case uploading, staged, landed; var caption: String }`；`TransferState.phase`；`TransferState.caption` 新文案；`struct TransferTally { uploading, failed, staged, landed; total; static func of(_:) }`。

- [ ] **Step 1: project.yml 加测试 target**

在 `targets:` 末尾追加：

```yaml
  # 纯逻辑单测（阶段映射、图集分组、删除文案）。不参与 fastlane 归档。
  WorkdeckTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: Workdeck
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGNING_ALLOWED: NO
```

并把 `Workdeck` target 的 scheme 改成：

```yaml
    scheme:
      configVariants: []
      testTargets: [WorkdeckTests]
```

- [ ] **Step 2: 写失败的测试** `ios/Tests/TransferPhaseTests.swift`

```swift
import XCTest
@testable import Workdeck

final class TransferPhaseTests: XCTestCase {
    func testPhaseMapping() {
        XCTAssertEqual(TransferState.waiting.phase, .uploading)
        XCTAssertEqual(TransferState.moving.phase, .uploading)
        XCTAssertEqual(TransferState.failed.phase, .uploading)
        XCTAssertEqual(TransferState.uploaded.phase, .staged)
        XCTAssertEqual(TransferState.arrived.phase, .landed)
    }

    func testCaptions() {
        XCTAssertEqual(TransferPhase.uploading.caption, "上传中")
        XCTAssertEqual(TransferPhase.staged.caption, "已暂存")
        XCTAssertEqual(TransferPhase.landed.caption, "已落盘")
        XCTAssertEqual(TransferState.failed.caption, "上传失败")
        XCTAssertEqual(TransferState.waiting.caption, "上传中")
        XCTAssertEqual(TransferState.uploaded.caption, "已暂存")
        XCTAssertEqual(TransferState.arrived.caption, "已落盘")
    }

    func testTallyCountsFailedInsideUploading() {
        let items = [
            TestItems.make(.waiting), TestItems.make(.failed), TestItems.make(.moving),
            TestItems.make(.uploaded), TestItems.make(.arrived), TestItems.make(.arrived),
        ]
        let t = TransferTally.of(items)
        XCTAssertEqual(t.uploading, 3)
        XCTAssertEqual(t.failed, 1)
        XCTAssertEqual(t.staged, 1)
        XCTAssertEqual(t.landed, 2)
        XCTAssertEqual(t.total, 6)
    }
}

/// 测试用造件。project 与时间可指定，其余字段无关紧要。
enum TestItems {
    static func make(_ state: TransferState, project: RelayProject? = nil,
                     at: Date = Date(), kind: MediaKind = .photo) -> CaptureItem {
        let id = UUID()
        return CaptureItem(
            id: id, kind: kind, state: state,
            manifest: CaptureManifest(
                clientMediaId: id, sha256: String(repeating: "a", count: 64),
                capturedAt: at, serverReceivedAt: nil, latitude: nil, longitude: nil,
                horizontalAccuracy: nil, deviceModel: "x", osVersion: "x", appVersion: "x",
                fromCamera: true, tsaToken: nil),
            localURL: URL(fileURLWithPath: "/dev/null"), progress: 0,
            lastError: nil, savedToAlbum: false, project: project)
    }
}
```

- [ ] **Step 3: 生成工程并跑测试，确认编译失败**

```bash
cd ios && xcodegen generate && cd .. && xcodebuild test -project ios/Workdeck.xcodeproj -scheme Workdeck -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:WorkdeckTests CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
预期：编译错误（`TransferPhase` 不存在、`CaptureItem` 无 `project`）。

- [ ] **Step 4: 改 CaptureItem.swift**

`TransferState.caption` 改为：

```swift
    var caption: String {
        switch self {
        case .waiting, .moving: "上传中"
        case .uploaded: "已暂存"
        case .arrived: "已落盘"
        case .failed: "上传失败"
        }
    }

    /// 展示层三段。内部五态是状态机与存储契约，界面上只说三段：
    /// 在手机上（含排队、传输、失败）/ 在云端等电脑 / 已在电脑上。
    var phase: TransferPhase {
        switch self {
        case .waiting, .moving, .failed: .uploading
        case .uploaded: .staged
        case .arrived: .landed
        }
    }
```

在 `TransferState` 之后新增：

```swift
enum TransferPhase: String, CaseIterable, Sendable {
    case uploading, staged, landed

    var caption: String {
        switch self {
        case .uploading: "上传中"
        case .staged: "已暂存"
        case .landed: "已落盘"
        }
    }
}
```

`CaptureItem` 增加字段（放在 `savedToAlbum` 之后）：

```swift
    /// 归档去向。拍摄那一刻的选中项目，之后切项目不影响它。
    /// 旧记录没有这个字段（nil），上传时用当时的选中项目并写回。
    let project: RelayProject?

    /// 图集分组用的项目键。旧记录无项目 → "unknown"。
    var projectID: String { project?.id ?? LibraryProject.unknownID }
```

`TransferTally` 整个替换为：

```swift
/// 三段各有多少件。failed 是 uploading 的子集，用来在桶上标「含 N 失败」。
struct TransferTally: Sendable, Equatable {
    var uploading: Int
    var failed: Int
    var staged: Int
    var landed: Int

    var total: Int { uploading + staged + landed }

    static let zero = TransferTally(uploading: 0, failed: 0, staged: 0, landed: 0)

    static func of(_ items: [CaptureItem]) -> TransferTally {
        var t = TransferTally.zero
        for i in items {
            switch i.state.phase {
            case .uploading: t.uploading += 1
            case .staged: t.staged += 1
            case .landed: t.landed += 1
            }
            if i.state == .failed { t.failed += 1 }
        }
        return t
    }
}
```

在文件末尾新增：

```swift
/// 图集里的「一个项目」。与 RelayProject 的区别：多一个「未知项目」桶给旧记录。
struct LibraryProject: Identifiable, Hashable, Sendable {
    static let unknownID = "unknown"
    let id: String
    let name: String

    static let unknown = LibraryProject(id: unknownID, name: "未知项目")
    init(id: String, name: String) { self.id = id; self.name = name }
    init(_ p: RelayProject) { self.init(id: p.id, name: p.name) }
}
```

- [ ] **Step 5: 修 DemoData 与 EvidenceStore 里的 CaptureItem 构造让工程能编译**

`DemoData.tally` 改为 `TransferTally(uploading: 12, failed: 1, staged: 3, landed: 148)`；
`DemoData.recent` 的 `CaptureItem(...)` 末尾加 `project: DemoData.relay`，并在 `DemoData` 里加：

```swift
    static let relay = RelayProject(deviceId: "dev-1", deviceName: "MacBook Pro",
                                    key: "p-1", name: "华创科技 A 轮尽调")
```

`EvidenceStore.save` 里的 `CaptureItem(...)` 与 `decode` 里的 `CaptureItem(...)` 先各加 `project: nil`（Task 2 会接真值）。`EvidenceStore.tally()` 先改成用 `TransferTally.of(all)`（Task 3 删掉）。

- [ ] **Step 6: 跑测试通过**

同 Step 3 命令。预期：`Test Suite 'TransferPhaseTests' passed`。

- [ ] **Step 7: 提交**

```bash
git add ios/project.yml ios/Sources/Model/CaptureItem.swift ios/Tests/TransferPhaseTests.swift ios/Sources/App/DemoData.swift ios/Sources/Services/EvidenceStore.swift
git commit -m "feat(ios): 传输阶段三段映射 + 单测 target（dev-board#384）"
```

---

### Task 2: iOS 影像绑定项目（#383）

**Files:**
- Modify: `ios/Sources/Services/EvidenceStore.swift`
- Modify: `ios/Sources/Services/UploadQueue.swift`
- Modify: `ios/Sources/App/AppModel.swift`

**Interfaces:**
- Produces: `EvidenceStore.save(data:kind:capturedAt:location:device:project:)`；`EvidenceStore.setProject(_ id: UUID, _ project: RelayProject)`；`EvidenceStore.delete(ids: [UUID])`。
- Consumes: `CaptureItem.project`（Task 1）。

- [ ] **Step 1: EvidenceStore 持久化项目**

`StoredRow` 加 `var project: RelayProject?`（放在 `savedToAlbum` 后，注释同上「老记录没有」）。
`save` 签名加 `project: RelayProject?`，构造 `CaptureItem(... savedToAlbum: false, project: project)`。
`decode` 传 `project: row.project`；`writeManifest` 传 `project: item.project`。
新增两个方法（放 `markSavedToAlbum` 后）：

```swift
    /// 旧记录上传时补记实际去向。只在 project 为 nil 时写，不覆盖已有归属。
    func setProject(_ id: UUID, _ project: RelayProject) throws {
        guard let item = try? loadOne(id), item.project == nil else { return }
        let updated = CaptureItem(
            id: item.id, kind: item.kind, state: item.state, manifest: item.manifest,
            localURL: item.localURL, progress: item.progress, lastError: item.lastError,
            savedToAlbum: item.savedToAlbum, project: project)
        try writeManifest(updated)
    }

    /// 用户主动删除：原图与记录一起删。记录留着而图没了，图集里会出现永远打不开的空格。
    func delete(ids: [UUID]) {
        for id in ids {
            guard let item = try? loadOne(id) else { continue }
            try? fm.removeItem(at: item.localURL)
            try? fm.removeItem(at: manifestDir.appendingPathComponent("\(id.uuidString).json"))
        }
    }
```

- [ ] **Step 2: UploadQueue 按件内项目上传**

`kick()` 里 `guard !running, let project else { return }` 改为 `guard !running else { return }`。
循环内：

```swift
        while true {
            // 目标项目按件走：旧记录没记项目的沿用当前选中项目并写回；两者都没有的跳过
            let pending = (try? await EvidenceStore.shared.loadAll())?
                .filter { $0.state == .waiting && ($0.project != nil || project != nil) } ?? []
            guard let item = pending.last else { break }   // 先传最早拍的
            let target: RelayProject
            if let p = item.project {
                target = p
            } else {
                target = project!
                try? await EvidenceStore.shared.setProject(item.id, target)
            }

            do {
                try await EvidenceStore.shared.updateState(item.id, to: .moving, progress: 0)
                await onChange?()

                try await API.shared.upload(
                    item: item,
                    project: target,
                    fileName: Self.fileName(for: item)
                ) { _ in }
```

其余不变。`configure` 的注释改为：「project 只给旧记录做兜底目标，正常件各自带项目」。

- [ ] **Step 3: AppModel 传项目、改注释**

`store(...)` 里 `EvidenceStore.shared.save(... device: Device.facts, project: selectedProject)`。
`clearProjectSelection` 注释改为：

```swift
    /// 切项目：清掉选择回到选择页。已拍的影像各自记着自己的项目，切项目不改变它们的去向。
```

- [ ] **Step 4: 构建通过**

```bash
xcodebuild build -project ios/Workdeck.xcodeproj -scheme Workdeck -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head
```
预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 5: 提交**

```bash
git add ios/Sources/Services/EvidenceStore.swift ios/Sources/Services/UploadQueue.swift ios/Sources/App/AppModel.swift
git commit -m "fix(ios): 影像记录绑定拍摄时的项目，上传按件内项目走（dev-board#383）"
```

---

### Task 3: iOS 分组纯函数 + 按项目计数

**Files:**
- Create: `ios/Sources/Model/LibraryGrouping.swift`
- Create: `ios/Tests/LibraryGroupingTests.swift`
- Modify: `ios/Sources/App/AppModel.swift`
- Modify: `ios/Sources/Services/EvidenceStore.swift`（删 `tally()`）

**Interfaces:**
- Produces:
  - `LibraryGrouping.projects(in: [CaptureItem], current: RelayProject?) -> [LibraryProject]`
  - `LibraryGrouping.items(_: [CaptureItem], in projectID: String) -> [CaptureItem]`
  - `struct DaySection: Identifiable { id: Date; title: String; items: [CaptureItem] }`；`LibraryGrouping.days(_: [CaptureItem], calendar:) -> [DaySection]`
  - `LibraryGrouping.deleteWarning(for: [CaptureItem]) -> String`
  - `AppModel.currentProjectID: String`、`AppModel.currentItems: [CaptureItem]`、`AppModel.tally: TransferTally`（计算属性）、`AppModel.otherPendingCount: Int`、`AppModel.delete(ids: [UUID]) async`

- [ ] **Step 1: 写失败的测试** `ios/Tests/LibraryGroupingTests.swift`

```swift
import XCTest
@testable import Workdeck

final class LibraryGroupingTests: XCTestCase {
    let a = RelayProject(deviceId: "d", deviceName: nil, key: "1", name: "甲项目")
    let b = RelayProject(deviceId: "d", deviceName: nil, key: "2", name: "乙项目")

    func testProjectsCurrentFirstUnknownLast() {
        let items = [
            TestItems.make(.arrived, project: b),
            TestItems.make(.arrived, project: nil),
            TestItems.make(.arrived, project: a),
        ]
        let ps = LibraryGrouping.projects(in: items, current: a)
        XCTAssertEqual(ps.map(\.id), [a.id, b.id, LibraryProject.unknownID])
        XCTAssertEqual(ps.last?.name, "未知项目")
    }

    func testProjectsIncludesCurrentEvenWithoutItems() {
        let ps = LibraryGrouping.projects(in: [TestItems.make(.arrived, project: b)], current: a)
        XCTAssertEqual(ps.map(\.id), [a.id, b.id])
    }

    func testItemsInProject() {
        let items = [TestItems.make(.arrived, project: a), TestItems.make(.arrived, project: b),
                     TestItems.make(.arrived, project: nil)]
        XCTAssertEqual(LibraryGrouping.items(items, in: a.id).count, 1)
        XCTAssertEqual(LibraryGrouping.items(items, in: LibraryProject.unknownID).count, 1)
    }

    func testDaysNewestFirstAndTitle() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let d1 = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 10))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 9))!
        let d2b = cal.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 15))!
        let items = [TestItems.make(.arrived, at: d1), TestItems.make(.arrived, at: d2),
                     TestItems.make(.arrived, at: d2b)]
        let days = LibraryGrouping.days(items, calendar: cal)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].title, "9月2日 · 2 件")
        XCTAssertEqual(days[0].items.map(\.capturedAt), [d2b, d2])
        XCTAssertEqual(days[1].title, "9月1日 · 1 件")
    }

    func testDeleteWarningByWorstPhase() {
        let landed = [TestItems.make(.arrived), TestItems.make(.arrived)]
        XCTAssertEqual(LibraryGrouping.deleteWarning(for: landed), "删除 2 件本地原图？电脑上已有副本。")
        let staged = landed + [TestItems.make(.uploaded)]
        XCTAssertEqual(LibraryGrouping.deleteWarning(for: staged),
                       "其中 1 件电脑还没取回。中转区 7 天后清理，电脑若未及时接收，这些影像将无法找回。")
        let uploading = staged + [TestItems.make(.failed), TestItems.make(.waiting)]
        XCTAssertEqual(LibraryGrouping.deleteWarning(for: uploading),
                       "其中 2 件还没送出去。删了就没了，无法找回。")
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**（命令同 Task 1 Step 3）

- [ ] **Step 3: 写 LibraryGrouping.swift**

```swift
import Foundation

/// 图集的分组与文案，全是纯函数——界面只负责画。
enum LibraryGrouping {
    /// 可切换的项目：当前项目永远第一（哪怕还没拍），其余有记录的按名称排，「未知项目」有记录时垫底。
    static func projects(in items: [CaptureItem], current: RelayProject?) -> [LibraryProject] {
        var seen: [String: LibraryProject] = [:]
        for i in items {
            if let p = i.project { seen[p.id] = LibraryProject(p) }
            else { seen[LibraryProject.unknownID] = .unknown }
        }
        var out: [LibraryProject] = []
        if let c = current {
            out.append(LibraryProject(c))
            seen[c.id] = nil
        }
        let unknown = seen.removeValue(forKey: LibraryProject.unknownID)
        out += seen.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let unknown { out.append(unknown) }
        return out
    }

    static func items(_ items: [CaptureItem], in projectID: String) -> [CaptureItem] {
        items.filter { $0.projectID == projectID }
    }

    struct DaySection: Identifiable {
        let id: Date
        let title: String
        let items: [CaptureItem]
    }

    /// 按自然日分段，新的在前；段内按拍摄时间倒序。
    static func days(_ items: [CaptureItem], calendar: Calendar = .current) -> [DaySection] {
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.capturedAt) }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "M月d日"
        return grouped.keys.sorted(by: >).map { day in
            let list = grouped[day]!.sorted { $0.capturedAt > $1.capturedAt }
            return DaySection(id: day, title: "\(f.string(from: day)) · \(list.count) 件", items: list)
        }
    }

    /// 删除确认文案，按所选里最坏的阶段说话。
    static func deleteWarning(for items: [CaptureItem]) -> String {
        let uploading = items.filter { $0.state.phase == .uploading }.count
        if uploading > 0 { return "其中 \(uploading) 件还没送出去。删了就没了，无法找回。" }
        let staged = items.filter { $0.state.phase == .staged }.count
        if staged > 0 {
            return "其中 \(staged) 件电脑还没取回。中转区 7 天后清理，电脑若未及时接收，这些影像将无法找回。"
        }
        return "删除 \(items.count) 件本地原图？电脑上已有副本。"
    }
}
```

- [ ] **Step 4: AppModel 改为按项目派生**

删掉 `var tally: TransferTally = .zero`，改为：

```swift
    /// 当前项目的键。图集与计数只看它。
    var currentProjectID: String { selectedProject?.id ?? LibraryProject.unknownID }
    var currentItems: [CaptureItem] { LibraryGrouping.items(items, in: currentProjectID) }
    /// 三段计数，只数当前项目——进度跟着项目走。
    var tally: TransferTally { TransferTally.of(currentItems) }
    /// 别的项目里还没落盘的件数。队列页末尾提一句，免得它们被完全藏起来。
    var otherPendingCount: Int {
        items.filter { $0.projectID != currentProjectID && $0.state != .arrived }.count
    }

    func delete(ids: [UUID]) async {
        await EvidenceStore.shared.delete(ids: ids)
        await refresh()
    }
```

`refresh()` 改为只读 `loadAll()`：

```swift
    func refresh() async {
        do {
            items = try await EvidenceStore.shared.loadAll()
        } catch {
            // 读不出来不该清空界面——宁可显示上一次的状态，也不要让用户以为照片没了
        }
    }
```

删掉 `EvidenceStore.tally()`。

- [ ] **Step 5: 跑测试通过；构建通过**（HomeView/LibraryView 引用 `tally.waiting` 会报错——先把 HomeView 的 `tallyLine`/`counter` 与 LibraryView 的 `tallyRow` 三处临时改成 `tally.uploading / tally.staged / tally.landed`，Task 4/5 再整理文案。）

- [ ] **Step 6: 提交**

```bash
git add ios/Sources/Model/LibraryGrouping.swift ios/Tests/LibraryGroupingTests.swift ios/Sources/App/AppModel.swift ios/Sources/Services/EvidenceStore.swift ios/Sources/Features
git commit -m "feat(ios): 图集分组纯函数 + 计数按当前项目派生（dev-board#384/#385）"
```

---

### Task 4: iOS 首页、状态点、队列页改三态

**Files:**
- Modify: `ios/Sources/Design/Components.swift:31-52`
- Modify: `ios/Sources/Features/Home/HomeView.swift`（`tallyLine`、`count`、`libraryEntry`、`counter`）
- Modify: `ios/Sources/Features/Queue/QueueView.swift`

- [ ] **Step 1: StatusDot 点色**

```swift
    private var color: Color {
        switch state {
        // 排队与传输都是「还在手机上」：一个颜色，别让用户猜串行队列的内部细节
        case .waiting, .moving: onDark ? T.S.waitingOnDark : T.S.waiting
        // 已暂存：进了中转区但还没到电脑，绿点会撒谎
        case .uploaded: onDark ? T.S.movingOnDark : T.S.moving
        case .arrived: onDark ? T.S.arrivedOnDark : T.S.arrived
        case .failed: T.S.failed
        }
    }
```

- [ ] **Step 2: HomeView 计数行**

```swift
    private var tallyLine: some View {
        HStack(spacing: 0) {
            count(model.tally.uploading, "上传中", T.S.waitingOnDark, failed: model.tally.failed)
            divider
            count(model.tally.staged, "已暂存", T.S.movingOnDark)
            divider
            count(model.tally.landed, "已落盘", T.S.arrivedOnDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenQueue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tallyA11y)
        .accessibilityHint("查看上传队列")
        .accessibilityAddTraits(.isButton)
    }

    private var tallyA11y: String {
        let t = model.tally
        let failed = t.failed > 0 ? "，其中 \(t.failed) 张失败" : ""
        return "上传中 \(t.uploading) 张\(failed)，已暂存 \(t.staged) 张，已落盘 \(t.landed) 张"
    }

    private func count(_ n: Int, _ label: String, _ color: Color, failed: Int = 0) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(n)")
                .font(T.F.mono(13, .medium))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(T.F.nano())
                .foregroundStyle(.white.opacity(0.45))
            if failed > 0 {
                // 失败不单独成桶，但不能藏：云端满、会话过期这类不重试也不会好
                Text("含 \(failed) 失败")
                    .font(T.F.nano())
                    .foregroundStyle(T.S.failed)
            }
        }
    }
```

`libraryEntry` 里 `model.items.first` → `model.currentItems.first`，a11y 标签 `model.currentItems.count`；`counter` 里的数字改 `model.tally.total`。

- [ ] **Step 3: QueueView 只列当前项目 + 四分区 + 其他项目提示**

```swift
    private var scoped: [CaptureItem] { model.currentItems }
    private var failed: [CaptureItem] { scoped.filter { $0.state == .failed } }
    private var active: [CaptureItem] { scoped.filter { $0.state == .waiting || $0.state == .moving } }
    private var staged: [CaptureItem] { scoped.filter { $0.state == .uploaded } }
    private var landed: [CaptureItem] { scoped.filter { $0.state == .arrived } }
```

body 里的分区：

```swift
                    if !failed.isEmpty { section("失败 · 需要处理", failed, tint: T.S.failed) }
                    if !active.isEmpty { section("上传中", active, tint: T.S.waiting) }
                    if !staged.isEmpty { section("已暂存 · 等电脑取回", staged, tint: T.S.moving) }
                    if !landed.isEmpty { section("已落盘", landed, tint: T.S.arrived) }
                    if scoped.isEmpty { empty }
                    if model.otherPendingCount > 0 { otherProjectsNote }
```

新增：

```swift
    /// 队列只看当前项目，但别的项目的未落盘件不能完全藏起来——至少说一声有多少。
    private var otherProjectsNote: some View {
        Text("其他项目还有 \(model.otherPendingCount) 件未落盘，切换项目后可见。")
            .font(T.F.nano())
            .foregroundStyle(T.L.fgFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, T.Sp.s6)
    }
```

`.navigationTitle("上传队列")` 改为 `.navigationTitle(model.project.name)` 并加 `.navigationSubtitle`？（iOS 17 无此 API）——保持 `"上传队列"`，在 toolbar 的 `principal` 位放两行：

```swift
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("上传队列").font(T.F.heading()).foregroundStyle(T.L.fg)
                        Text(model.project.name).font(T.F.nano()).foregroundStyle(T.L.fgFaint).lineLimit(1)
                    }
                }
```

「全部重试」按钮条件仍用 `failed`（当前项目）。`row` 里 `Text(item.state.caption)` 不改（文案已由 Task 1 更新）。空态文案「拍摄后会自动排队上传到当前项目。」保留。

- [ ] **Step 4: 构建通过**（命令同 Task 2 Step 4）

- [ ] **Step 5: 提交**

```bash
git add ios/Sources/Design/Components.swift ios/Sources/Features/Home/HomeView.swift ios/Sources/Features/Queue/QueueView.swift
git commit -m "feat(ios): 首页与队列页改三态文案，只数当前项目（dev-board#384）"
```

---

### Task 5: iOS 图集重做（#385 + #386）

**Files:**
- Rewrite: `ios/Sources/Features/Library/LibraryView.swift`
- Modify: `ios/Sources/App/WorkdeckApp.swift:64-72`

**Interfaces:**
- Consumes: `LibraryGrouping.*`、`AppModel.currentProjectID / items / tally / delete(ids:)`、`TransferTally.of`、`EvidenceThumb`、`StatusDot`。
- Produces: `LibraryView(onClose:)`。

- [ ] **Step 1: RootView 改调用**

```swift
            case .library:
                LibraryView(onClose: { route = nil })
                    .environment(model)
                    .preferredColorScheme(.dark)
```

- [ ] **Step 2: 重写 LibraryView.swift**

```swift
import SwiftUI

/// 影像浏览 —— 方向 B「影像优先」。深色，影像铺满，玻璃条压在影像上。
///
/// 只看一个项目：默认当前项目，顶栏可切换看别的项目（只切看的对象，不切拍摄目标）。
/// 项目内按自然日分段。列数、网格/列表、多选删除都在这一页。
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    var onClose: () -> Void

    @State private var viewingID: String?
    @AppStorage("libraryColumns") private var columns = 3
    @AppStorage("libraryViewMode") private var viewMode = "grid"
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - 派生

    private var projects: [LibraryProject] {
        LibraryGrouping.projects(in: model.items, current: model.selectedProject)
    }
    private var viewing: LibraryProject {
        let id = viewingID ?? model.currentProjectID
        return projects.first { $0.id == id } ?? projects.first ?? .unknown
    }
    private var items: [CaptureItem] { LibraryGrouping.items(model.items, in: viewing.id) }
    private var days: [LibraryGrouping.DaySection] { LibraryGrouping.days(items) }
    private var tally: TransferTally { TransferTally.of(items) }
    private var selectedItems: [CaptureItem] { items.filter { selected.contains($0.id) } }
    private var isGrid: Bool { viewMode == "grid" }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 1.5), count: max(2, min(4, columns)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            T.D.bg.ignoresSafeArea()

            ScrollView {
                if items.isEmpty {
                    emptyState
                } else if isGrid {
                    grid
                } else {
                    list
                }
            }
            .scrollIndicators(.hidden)

            topBar
        }
        .overlay(alignment: .bottom) { selecting ? AnyView(deleteDock) : AnyView(dock) }
        .onAppear { appeared = true }
        .confirmationDialog(
            LibraryGrouping.deleteWarning(for: selectedItems),
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                let ids = Array(selected)
                selected = []
                selecting = false
                Task { await model.delete(ids: ids) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 网格

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: 1.5, pinnedViews: [.sectionHeaders]) {
            ForEach(days) { day in
                Section {
                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                        cell(item)
                            .opacity(appeared || reduceMotion ? 1 : 0)
                            .offset(y: appeared || reduceMotion ? 0 : 10)
                            .animation(T.A.rise.delay(Double(min(index, 12)) * 0.045), value: appeared)
                    }
                } header: {
                    dayHeader(day)
                }
            }
        }
        // 顶栏与底座都是浮层，内容要自己让开，否则首末两行永远被压住
        .padding(.top, 96)
        .padding(.bottom, 130)
    }

    private func cell(_ item: CaptureItem) -> some View {
        let checked = selected.contains(item.id)
        return EvidenceThumb(item: item, onDark: true)
            .aspectRatio(1, contentMode: .fill)
            .overlay(alignment: .topTrailing) {
                StatusDot(state: item.state, onDark: true).padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                Text(RelativeTime.clock(item.capturedAt))
                    .font(T.F.mono(10))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(8)
            }
            .overlay(alignment: .bottom) {
                if item.state == .moving {
                    // 进度直接画在图上。单独开一栏进度条会把注意力从影像上拉走。
                    GeometryReader { geo in
                        Rectangle()
                            .fill(T.S.movingOnDark)
                            .frame(width: geo.size.width * item.progress, height: 2)
                    }
                    .frame(height: 2)
                }
            }
            .overlay { if selecting { selectionMark(checked) } }
            .contentShape(Rectangle())
            .onTapGesture { if selecting { toggle(item.id) } }
            .accessibilityElement()
            .accessibilityLabel("\(kindLabel(item.kind))，\(RelativeTime.clock(item.capturedAt))，\(item.state.caption)")
            .accessibilityAddTraits(selecting && checked ? [.isButton, .isSelected] : selecting ? .isButton : [])
    }

    private func selectionMark(_ checked: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(checked ? 0.35 : 0)
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(checked ? T.S.movingOnDark : .white.opacity(0.8))
                .padding(8)
        }
    }

    private func dayHeader(_ day: LibraryGrouping.DaySection) -> some View {
        HStack {
            Eyebrow(text: day.title, color: .white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, T.Sp.gutter)
        .padding(.vertical, T.Sp.s2)
        .background(T.D.bg.opacity(0.92))
    }

    // MARK: - 列表

    private var list: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(days) { day in
                Section {
                    ForEach(day.items) { item in
                        row(item)
                        Hairline(color: T.D.rule)
                    }
                } header: {
                    dayHeader(day)
                }
            }
        }
        .padding(.top, 96)
        .padding(.bottom, 130)
    }

    private func row(_ item: CaptureItem) -> some View {
        let checked = selected.contains(item.id)
        return HStack(alignment: .top, spacing: T.Sp.s3) {
            if selecting {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(checked ? T.S.movingOnDark : .white.opacity(0.5))
                    .frame(width: 24, height: 44)
            }
            EvidenceThumb(item: item, onDark: true).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: T.Sp.s1) {
                    StatusDot(state: item.state, size: 5, onDark: true)
                    Text(item.state.caption).font(T.F.small()).foregroundStyle(T.D.fg)
                    Text(RelativeTime.clock(item.capturedAt)).font(T.F.mono(11)).foregroundStyle(T.D.fgMuted)
                }
                if let err = item.lastError, item.state == .failed {
                    Text(err).font(T.F.nano()).foregroundStyle(T.S.failed)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.manifest.sha256.prefix(12)).font(T.F.mono(10)).foregroundStyle(T.D.fgMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, T.Sp.gutter)
        .padding(.vertical, T.Sp.s3)
        .contentShape(Rectangle())
        .onTapGesture { if selecting { toggle(item.id) } }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: T.Sp.s2) {
            Text("这个项目还没有影像").font(T.F.body()).foregroundStyle(T.D.fg)
            Text("拍摄后会归入当前项目。").font(T.F.micro()).foregroundStyle(T.D.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.Sp.gutter)
        .padding(.top, 96 + T.Sp.s10)
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func kindLabel(_ kind: MediaKind) -> String {
        switch kind {
        case .photo: "照片"
        case .video: "录像"
        case .audio: "录音"
        }
    }

    // MARK: - 顶栏（玻璃压在影像上）

    private var topBar: some View {
        HStack(spacing: T.Sp.s3) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(T.D.fg)
                    .frame(width: T.touchMin, height: T.touchMin)
            }
            .accessibilityLabel("返回")

            VStack(alignment: .leading, spacing: 2) {
                projectMenu
                tallyRow
            }
            Spacer(minLength: 0)
            tools
        }
        .padding(.leading, T.Sp.s2)
        .padding(.trailing, T.Sp.s3)
        .padding(.bottom, T.Sp.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(alignment: .bottom) { Hairline(color: T.D.rule) }
                .ignoresSafeArea(edges: .top)
        }
    }

    /// 项目名就是切换入口。只切看的对象，不动拍摄目标。
    private var projectMenu: some View {
        Menu {
            ForEach(projects) { p in
                Button {
                    viewingID = p.id
                    selected = []
                } label: {
                    if p.id == viewing.id { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewing.name).font(T.F.heading()).kerning(-0.2).foregroundStyle(T.D.fg).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(T.D.fgMuted)
            }
        }
        .accessibilityLabel("正在看 \(viewing.name)，切换项目")
    }

    private var tallyRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            pill(tally.uploading, "上传中", T.S.waitingOnDark)
            if tally.failed > 0 {
                Text("含 \(tally.failed) 失败").font(T.F.nano()).foregroundStyle(T.S.failed).padding(.trailing, T.Sp.s2)
            }
            pill(tally.staged, "已暂存", T.S.movingOnDark)
            pill(tally.landed, "已落盘", T.S.arrivedOnDark)
        }
        .accessibilityElement(children: .combine)
    }

    private func pill(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Text("\(n)").font(T.F.mono(13, .medium)).monospacedDigit().foregroundStyle(color)
            Text(label).font(T.F.nano()).foregroundStyle(T.D.fgMuted)
        }
        .padding(.trailing, T.Sp.s2)
    }

    /// 列数 → 视图 → 选择。三个小按钮，不做工具栏。
    private var tools: some View {
        HStack(spacing: 0) {
            if isGrid && !selecting {
                toolButton(columns == 2 ? "square.grid.2x2" : columns == 3 ? "square.grid.3x3" : "square.grid.4x3.fill",
                           label: "\(columns) 列，切换列数") {
                    columns = columns >= 4 ? 2 : columns + 1
                }
            }
            if !selecting {
                toolButton(isGrid ? "list.bullet" : "square.grid.2x2", label: isGrid ? "切换到列表" : "切换到网格") {
                    viewMode = isGrid ? "list" : "grid"
                }
            }
            Button(selecting ? "取消" : "选择") {
                selecting.toggle()
                selected = []
            }
            .font(T.F.small())
            .foregroundStyle(T.D.fg)
            .frame(minWidth: T.touchMin, minHeight: T.touchMin)
            .disabled(items.isEmpty)
        }
    }

    private func toolButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(T.D.fg)
                .frame(width: T.touchMin, height: T.touchMin)
        }
        .accessibilityLabel(label)
    }

    // MARK: - 底座

    private var dock: some View {
        HStack {
            HStack(spacing: T.Sp.s1) {
                BreathingDot(isOn: model.link.isOnline, color: T.S.arrivedOnDark)
                Text(model.link.isOnline ? "桌面端在线" : "桌面端离线")
                    .font(T.F.nano()).tracking(0.6).foregroundStyle(T.D.fgMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 首页现在就是取景器：这里的快门收回浏览页即回到镜头
            ShutterButton(action: onClose)

            Text(model.project.archivePath)
                .font(T.F.nano()).tracking(0.6).foregroundStyle(T.D.fgMuted).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, T.Sp.gutter)
        .padding(.top, T.Sp.s3)
        .padding(.bottom, T.Sp.s2)
        .background { dockBackground }
    }

    private var deleteDock: some View {
        HStack {
            Text(selected.isEmpty ? "点选要删除的影像" : "已选 \(selected.count) 件")
                .font(T.F.small()).foregroundStyle(T.D.fgMuted)
            Spacer()
            Button {
                confirmDelete = true
            } label: {
                Text("删除 \(selected.count) 件")
                    .font(T.F.small())
                    .foregroundStyle(.white)
                    .padding(.horizontal, T.Sp.s4)
                    .frame(minHeight: T.touchMin)
                    .background(T.S.failed, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, T.Sp.gutter)
        .padding(.top, T.Sp.s3)
        .padding(.bottom, T.Sp.s2)
        .background { dockBackground }
    }

    private var dockBackground: some View {
        LinearGradient(colors: [T.D.bg.opacity(0), T.D.bg.opacity(0.94)], startPoint: .top, endPoint: .bottom)
            .background(.ultraThinMaterial.opacity(0.6))
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea(edges: .bottom)
    }
}
```

`ShutterButton` 与 `#Preview` 保留（Preview 改成 `LibraryView(onClose: {}).environment(AppModel())`）。

- [ ] **Step 3: 构建通过；单测通过**

- [ ] **Step 4: 模拟器走查**：`xcodebuild build` 后用 iOS Simulator 工具 launch，切项目拍两张、切另一项目拍一张、开图集：只见当前项目；菜单切项目；列数与视图切换；选择两件删除，确认文案含「还没送出去」（离线时件在上传中）。

- [ ] **Step 5: 提交**

```bash
git add ios/Sources/Features/Library/LibraryView.swift ios/Sources/App/WorkdeckApp.swift
git commit -m "feat(ios): 图集按项目看、按日分段，列数/视图切换与多选删除（dev-board#385/#386）"
```

---

### Task 6: 小程序纯函数 phase.ts + 测试

**Files:**
- Create: `miniprogram/utils/phase.ts`
- Create: `tests/phase.test.ts`
- Modify: `package.json`

**Interfaces:**
- Produces（全部从 `phase.ts` 导出）：
  - `type QueueState`、`type Phase = 'uploading' | 'staged' | 'landed'`
  - `phaseOf(state): Phase`、`PHASE_LABEL: Record<Phase, string>`、`stateText(state): string`、`dotClass(state): string`
  - `interface Tally { uploading; failed; staged; landed }`、`tallyOf(items: Array<{state}>): Tally`、`tallyTotal(t): number`
  - `projectId(p: { deviceId: string; projectKey: string }): string`
  - `interface DaySection<T> { key: string; title: string; items: T[] }`、`groupByDay(items: Array<T & {createdAt:number}>): DaySection<T>[]`
  - `deleteWarning(states: QueueState[]): string`
  - `projectsIn(items: Array<{deviceId; projectKey; projectName}>, current: {deviceId; key; name}): Array<{ id: string; name: string }>`

- [ ] **Step 1: package.json 加脚本** `"test": "node --test tests/"`

- [ ] **Step 2: 写失败的测试** `tests/phase.test.ts`

```ts
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  phaseOf, stateText, dotClass, tallyOf, tallyTotal, projectId,
  groupByDay, deleteWarning, projectsIn,
} from '../miniprogram/utils/phase.ts'

test('phase mapping', () => {
  assert.equal(phaseOf('waiting'), 'uploading')
  assert.equal(phaseOf('uploading'), 'uploading')
  assert.equal(phaseOf('failed'), 'uploading')
  assert.equal(phaseOf('uploaded'), 'staged')
  assert.equal(phaseOf('arrived'), 'landed')
})

test('state text and dot class', () => {
  assert.equal(stateText('waiting'), '上传中')
  assert.equal(stateText('failed'), '上传失败')
  assert.equal(stateText('uploaded'), '已暂存 · 等待桌面端接收')
  assert.equal(stateText('arrived'), '已落盘')
  assert.equal(dotClass('waiting'), 'dot--waiting')
  assert.equal(dotClass('uploading'), 'dot--waiting')
  assert.equal(dotClass('uploaded'), 'dot--moving')
  assert.equal(dotClass('arrived'), 'dot--arrived')
  assert.equal(dotClass('failed'), 'dot--failed')
})

test('tally counts failed inside uploading', () => {
  const t = tallyOf([
    { state: 'waiting' }, { state: 'failed' }, { state: 'uploading' },
    { state: 'uploaded' }, { state: 'arrived' }, { state: 'arrived' },
  ])
  assert.deepEqual(t, { uploading: 3, failed: 1, staged: 1, landed: 2 })
  assert.equal(tallyTotal(t), 6)
})

test('projectId joins deviceId and key', () => {
  assert.equal(projectId({ deviceId: 'd', projectKey: '7' }), 'd:7')
})

test('groupByDay newest first with title', () => {
  const at = (m: number, d: number, h: number) => new Date(2026, m - 1, d, h).getTime()
  const days = groupByDay([
    { createdAt: at(9, 1, 10) }, { createdAt: at(9, 2, 9) }, { createdAt: at(9, 2, 15) },
  ])
  assert.equal(days.length, 2)
  assert.equal(days[0].title, '9月2日 · 2 件')
  assert.deepEqual(days[0].items.map((i) => i.createdAt), [at(9, 2, 15), at(9, 2, 9)])
  assert.equal(days[1].title, '9月1日 · 1 件')
})

test('deleteWarning by worst phase', () => {
  assert.equal(deleteWarning(['arrived', 'arrived']), '删除 2 件本地原图？电脑上已有副本。')
  assert.equal(deleteWarning(['arrived', 'uploaded']),
    '其中 1 件电脑还没取回。中转区 7 天后清理，电脑若未及时接收，这些影像将无法找回。')
  assert.equal(deleteWarning(['uploaded', 'failed', 'waiting']),
    '其中 2 件还没送出去。删了就没了，无法找回。')
})

test('projectsIn current first, others by name', () => {
  const cur = { deviceId: 'd', key: '1', name: '甲' }
  const ps = projectsIn([
    { deviceId: 'd', projectKey: '3', projectName: '丙' },
    { deviceId: 'd', projectKey: '2', projectName: '乙' },
    { deviceId: 'd', projectKey: '1', projectName: '甲' },
  ], cur)
  assert.deepEqual(ps.map((p) => p.id), ['d:1', 'd:2', 'd:3'])
  assert.deepEqual(projectsIn([], cur), [{ id: 'd:1', name: '甲' }])
})
```

- [ ] **Step 3: 跑 `npm test`，预期失败（模块不存在）**

- [ ] **Step 4: 写 phase.ts**

```ts
/**
 * 传输阶段的展示层 —— 纯函数，不碰 wx，两端文案一致（对齐 iOS TransferPhase）。
 *
 * 内部五态（QueueState）是状态机与存储契约，不改；界面上只说三段：
 * 上传中（在手机上，含排队/传输/失败）/ 已暂存（云端等电脑）/ 已落盘（已在电脑上）。
 */

export type QueueState = 'waiting' | 'uploading' | 'uploaded' | 'arrived' | 'failed'
export type Phase = 'uploading' | 'staged' | 'landed'

export const PHASE_LABEL: Record<Phase, string> = {
  uploading: '上传中',
  staged: '已暂存',
  landed: '已落盘',
}

export function phaseOf(state: QueueState): Phase {
  if (state === 'uploaded') return 'staged'
  if (state === 'arrived') return 'landed'
  return 'uploading'
}

export function stateText(state: QueueState): string {
  switch (state) {
    case 'waiting':
    case 'uploading':
      return '上传中'
    case 'failed':
      return '上传失败'
    case 'uploaded':
      return '已暂存 · 等待桌面端接收'
    case 'arrived':
      return '已落盘'
  }
}

/** 点色：排队与传输同色（都还在手机上）；已暂存用 moving 色；失败红。令牌名不改。 */
export function dotClass(state: QueueState): string {
  if (state === 'failed') return 'dot--failed'
  if (state === 'uploaded') return 'dot--moving'
  if (state === 'arrived') return 'dot--arrived'
  return 'dot--waiting'
}

export interface Tally {
  uploading: number
  failed: number
  staged: number
  landed: number
}

export function tallyOf(items: Array<{ state: QueueState }>): Tally {
  const t: Tally = { uploading: 0, failed: 0, staged: 0, landed: 0 }
  for (const it of items) {
    t[phaseOf(it.state)]++
    if (it.state === 'failed') t.failed++
  }
  return t
}

export function tallyTotal(t: Tally): number {
  return t.uploading + t.staged + t.landed
}

/** 项目标识：key 是桌面机本地 id，跨机同号不同物，必须连 deviceId。与 iOS RelayProject.id 同构。 */
export function projectId(p: { deviceId: string; projectKey: string }): string {
  return `${p.deviceId}:${p.projectKey}`
}

export interface DaySection<T> {
  key: string
  title: string
  items: T[]
}

/** 按本机自然日分段，新的在前；段内按时间倒序。 */
export function groupByDay<T extends { createdAt: number }>(items: T[]): DaySection<T>[] {
  const map = new Map<string, { day: Date; items: T[] }>()
  for (const it of items) {
    const d = new Date(it.createdAt)
    const key = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`
    let g = map.get(key)
    if (!g) {
      g = { day: new Date(d.getFullYear(), d.getMonth(), d.getDate()), items: [] }
      map.set(key, g)
    }
    g.items.push(it)
  }
  return Array.from(map.entries())
    .sort((a, b) => b[1].day.getTime() - a[1].day.getTime())
    .map(([key, g]) => {
      const list = g.items.slice().sort((a, b) => b.createdAt - a.createdAt)
      return { key, title: `${g.day.getMonth() + 1}月${g.day.getDate()}日 · ${list.length} 件`, items: list }
    })
}

/** 删除确认文案，按所选里最坏的阶段说话。 */
export function deleteWarning(states: QueueState[]): string {
  const uploading = states.filter((s) => phaseOf(s) === 'uploading').length
  if (uploading > 0) return `其中 ${uploading} 件还没送出去。删了就没了，无法找回。`
  const staged = states.filter((s) => phaseOf(s) === 'staged').length
  if (staged > 0) return `其中 ${staged} 件电脑还没取回。中转区 7 天后清理，电脑若未及时接收，这些影像将无法找回。`
  return `删除 ${states.length} 件本地原图？电脑上已有副本。`
}

/** 可切换的项目：当前项目永远第一（哪怕还没拍），其余有记录的按名称排。 */
export function projectsIn(
  items: Array<{ deviceId: string; projectKey: string; projectName: string }>,
  current: { deviceId: string; key: string; name: string },
): Array<{ id: string; name: string }> {
  const curId = projectId({ deviceId: current.deviceId, projectKey: current.key })
  const seen = new Map<string, string>()
  for (const it of items) seen.set(projectId(it), it.projectName)
  seen.delete(curId)
  const rest = Array.from(seen.entries())
    .map(([id, name]) => ({ id, name }))
    .sort((a, b) => a.name.localeCompare(b.name, 'zh-Hans-CN'))
  return [{ id: curId, name: current.name }, ...rest]
}
```

- [ ] **Step 5: `npm test` 通过；`npm run typecheck` 通过**

- [ ] **Step 6: 提交**

```bash
git add miniprogram/utils/phase.ts tests/phase.test.ts package.json
git commit -m "feat(miniprogram): 传输阶段展示层纯函数 + node --test（dev-board#384）"
```

---

### Task 7: 小程序 queue.ts 按项目查询 + 删除 + 去掉自动删文件

**Files:**
- Modify: `miniprogram/utils/queue.ts`
- Create: `tests/queue-pure.test.ts`（不需要——queue.ts 依赖 wx，逻辑已在 phase.ts 覆盖；本任务靠 typecheck 与后续走查）

**Interfaces:**
- Produces: `listItems(projectId?: string): QueueItem[]`、`tallyFor(projectId: string): Tally`、`otherPendingCount(projectId: string): number`、`removeItems(ids: string[]): void`；`QueueState` 从 phase re-export。
- 删除：`counts()`。

- [ ] **Step 1: 改 queue.ts**

头部：

```ts
import { ApiError, getSession, mediaStatus, uploadMedia, uuid, type RelayProject } from './api'
import { projectId, tallyOf, type QueueState, type Tally } from './phase'

export type { QueueState } from './phase'
```

查询段替换 `listItems` 与 `counts`：

```ts
/** 新 → 旧。给 projectId 则只要该项目的。 */
export function listItems(projectIdFilter?: string): QueueItem[] {
  return readItems()
    .filter((it) => !projectIdFilter || projectId(it) === projectIdFilter)
    .sort((a, b) => b.createdAt - a.createdAt)
}

/** 三段计数，只数一个项目——进度跟着项目走。 */
export function tallyFor(projectIdFilter: string): Tally {
  return tallyOf(listItems(projectIdFilter))
}

/** 别的项目里还没落盘的件数。队列页末尾提一句，免得它们被完全藏起来。 */
export function otherPendingCount(projectIdFilter: string): number {
  return readItems().filter((it) => projectId(it) !== projectIdFilter && it.state !== 'arrived').length
}

/** 用户主动删除：原图（留底文件）与记录一起删。记录留着而图没了，图集里会出现永远打不开的空格。 */
export function removeItems(ids: string[]): void {
  const set = new Set(ids)
  const items = readItems()
  for (const it of items) {
    if (set.has(it.clientMediaId) && it.saved) removeSavedFile(it.filePath)
  }
  writeItems(items.filter((it) => !set.has(it.clientMediaId)))
}
```

`pollStatus` 里 delivered 分支删掉 `if (it.saved) removeSavedFile(it.filePath)`，并把 `removeSavedFile` 上方注释改为「用户删除时调用；抵达后不自动删——现场不可复现，与 iOS 同一口径」。

- [ ] **Step 2: `npm run typecheck`** —— index/queue 页还引用 `counts`，会报错；临时改成 `tallyFor(projectId({ deviceId: project.deviceId, projectKey: project.key }))`（Task 8 会正式整理）。

- [ ] **Step 3: 提交**

```bash
git add miniprogram/utils/queue.ts miniprogram/pages
git commit -m "feat(miniprogram): 队列按项目查询、用户删除记录，抵达后不再自动删留底（dev-board#384/#386）"
```

---

### Task 8: 小程序首页与队列页改三态、只看当前项目

**Files:**
- Modify: `miniprogram/pages/index/index.ts`（`refresh`、`toDisplayState`、`onOpenQueue` 保留、新增 `onOpenGallery`）
- Modify: `miniprogram/pages/index/index.wxml:16-31, 104`
- Modify: `miniprogram/pages/index/index.wxss`（加 `.top__failed`、`.ctrl__recent-dot--failed`）
- Modify: `miniprogram/pages/queue/queue.ts|wxml|wxss`

- [ ] **Step 1: index.ts**

import 改：`import { listItems, tallyFor, subscribe, pollStatus, processQueue, enqueueCapture, type QueueItem } from '../../utils/queue'` 与 `import { dotClass, projectId, tallyTotal, type Tally } from '../../utils/phase'`。

`data.counts` 改为 `tally: { uploading: 0, failed: 0, staged: 0, landed: 0 } as Tally, total: 0`。
`RecentDisplay.state` 改为 `dotClass: string`；删掉 `toDisplayState`。

```ts
  refresh() {
    const project = getSelectedProject()
    if (!project) return
    const pid = projectId({ deviceId: project.deviceId, projectKey: project.key })
    const latest = listItems(pid)[0]
    const recent: RecentDisplay | null = latest
      ? {
          id: latest.clientMediaId,
          thumb: thumbFor(latest),
          icon: placeholderIcon(latest.mediaType),
          dotClass: dotClass(latest.state),
        }
      : null
    const tally = tallyFor(pid)
    this.setData({ tally, total: tallyTotal(tally), recent })
  },
```

导航段加：

```ts
  onOpenGallery() {
    wx.navigateTo({ url: '/pages/gallery/gallery' })
  },
```

- [ ] **Step 2: index.wxml**

顶部三个计数：

```xml
    <view class="top__stats tappable" bindtap="onOpenQueue">
      <view class="top__stat">
        <view class="top__dot top__dot--waiting"></view>
        <text class="top__num mono">{{tally.uploading}}</text>
        <text class="top__label">上传中</text>
        <text wx:if="{{tally.failed > 0}}" class="top__failed">含 {{tally.failed}} 失败</text>
      </view>
      <view class="top__stat">
        <view class="top__dot top__dot--moving"></view>
        <text class="top__num mono">{{tally.staged}}</text>
        <text class="top__label">已暂存</text>
      </view>
      <view class="top__stat">
        <view class="top__dot top__dot--arrived"></view>
        <text class="top__num mono">{{tally.landed}}</text>
        <text class="top__label">已落盘</text>
      </view>
    </view>
```

最近入口：`bindtap="onOpenGallery" aria-label="查看图集"`，点类 `class="ctrl__recent-dot {{recent.dotClass}}"`（把原来的 `ctrl__recent-dot--{{recent.state}}` 替换掉）。

- [ ] **Step 3: index.wxss**

在 `.top__dot` 规则后加：

```css
/* 失败不单独成桶，但不能藏：云端满、会话过期这类不重试也不会好 */
.top__failed {
  font-size: var(--t-nano);
  color: var(--st-failed);
}
```

找到 `.ctrl__recent-dot--waiting/--moving/--arrived` 三条，改成通用四条（保留原尺寸/定位规则不动）：

```css
.ctrl__recent-dot.dot--waiting { background: var(--st-waiting); }
.ctrl__recent-dot.dot--moving  { background: var(--st-moving); }
.ctrl__recent-dot.dot--arrived { background: var(--st-arrived); }
.ctrl__recent-dot.dot--failed  { background: var(--st-failed); }
```

- [ ] **Step 4: queue.ts**

import：`import { listItems, otherPendingCount, subscribe, pollStatus, retry, type QueueItem } from '../../utils/queue'`、`import { dotClass, phaseOf, projectId, stateText } from '../../utils/phase'`、`import { getSelectedProject } from '../../utils/api'`。删掉本地的 `statusText`、`dotClass`。`toDisplayItem` 里 `statusText: stateText(item.state)`、`dotClass: dotClass(item.state)`。

data 增加 `sections: [] as Array<{ title: string; items: DisplayItem[] }>`、`projectName: ''`、`otherPending: 0`；删掉 `items`。

```ts
  refresh() {
    const project = getSelectedProject()
    if (!project) return
    const pid = projectId({ deviceId: project.deviceId, projectKey: project.key })
    const all = listItems(pid)
    const pick = (f: (it: QueueItem) => boolean) => all.filter(f).map(toDisplayItem)
    const sections = [
      { title: '失败 · 需要处理', items: pick((it) => it.state === 'failed') },
      { title: '上传中', items: pick((it) => it.state === 'waiting' || it.state === 'uploading') },
      { title: '已暂存 · 等电脑取回', items: pick((it) => phaseOf(it.state) === 'staged') },
      { title: '已落盘', items: pick((it) => phaseOf(it.state) === 'landed') },
    ].filter((s) => s.items.length > 0)
    this.setData({ sections, projectName: project.name, otherPending: otherPendingCount(pid) })
  },
```

- [ ] **Step 5: queue.wxml**

```xml
<nav-bar title="上传队列" subtitle="{{projectName}}" show-back="{{true}}" scroll-top="{{scrollTop}}" />

<view class="page" style="padding-bottom: {{metrics.bottomInset}}px;">
  <view class="status" wx:if="{{!sections.length}}">
    <text class="status__text">这个项目还没有拍摄记录</text>
  </view>

  <view class="list" wx:else>
    <view class="section" wx:for="{{sections}}" wx:for-item="section" wx:key="title">
      <view class="section__head">
        <text class="label">{{section.title}}</text>
        <text class="section__count mono">{{section.items.length}}</text>
      </view>
      <view class="item" wx:for="{{section.items}}" wx:key="clientMediaId">
        <!-- 原 .item__row 内容原样保留 -->
        ...
      </view>
    </view>
  </view>

  <view class="other" wx:if="{{otherPending > 0}}">
    <text class="other__text">其他项目还有 {{otherPending}} 件未落盘，切换项目后可见。</text>
  </view>
</view>
```

（`...` 处照抄现有 `<view class="item__row">…</view><view class="rule"></view>`，并把 `item__meta` 里的 ` · {{item.projectName}}` 去掉——整页都是当前项目。）

- [ ] **Step 6: queue.wxss 加**

```css
.section { padding-top: var(--s5); }
.section__head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  padding-bottom: var(--s1);
}
.section__count {
  font-size: var(--t-micro);
  color: var(--fg-faint);
}
.other {
  padding: var(--s6) 0 var(--s4);
}
.other__text {
  font-size: var(--t-micro);
  color: var(--fg-faint);
  line-height: 1.5;
}
```

- [ ] **Step 7: `npm run typecheck` 通过**

- [ ] **Step 8: 提交**

```bash
git add miniprogram/pages/index miniprogram/pages/queue
git commit -m "feat(miniprogram): 首页与队列页改三态文案、只数当前项目（dev-board#384）"
```

---

### Task 9: 小程序图集页（#385 + #386）

**Files:**
- Create: `miniprogram/pages/gallery/gallery.json`、`gallery.ts`、`gallery.wxml`、`gallery.wxss`
- Modify: `miniprogram/app.json`（pages 加 `"pages/gallery/gallery"`）

**Interfaces:**
- Consumes: `listItems(pid)`、`removeItems`、`subscribe`、`pollStatus`；`phase.ts` 的 `groupByDay / projectsIn / projectId / tallyOf / dotClass / stateText / deleteWarning`；`thumbs.ts` 的 `thumbFor / markThumbBroken`；`nav-bar` 的 `action` slot 与 `titletap` 事件。

- [ ] **Step 1: gallery.json**

```json
{ "usingComponents": { "nav-bar": "/components/nav-bar/nav-bar" } }
```

- [ ] **Step 2: gallery.ts**

```ts
/**
 * 图集 —— 影像浏览走深色（D7）。只看一个项目：默认当前项目，点标题切换看别的项目
 * （只切看的对象，不切拍摄目标）。项目内按自然日分段。列数、网格/列表、多选删除都在这一页。
 * 队列契约不动，本页只读 listItems / 调 removeItems。
 */

import { Icon } from '../../utils/icons'
import type { Metrics } from '../../utils/layout'
import { getSelectedProject } from '../../utils/api'
import { listItems, removeItems, subscribe, pollStatus, type QueueItem } from '../../utils/queue'
import {
  deleteWarning, dotClass, groupByDay, projectId, projectsIn, stateText, tallyOf, type Tally,
} from '../../utils/phase'
import { thumbFor, markThumbBroken } from '../../utils/thumbs'

interface AppGlobal {
  globalData: { metrics: Metrics }
}

const POLL_INTERVAL = 5000
const KEY_COLS = 'awd.gallery.cols'
const KEY_VIEW = 'awd.gallery.view'

interface Cell {
  clientMediaId: string
  thumb: string
  kindIcon: string
  time: string
  statusText: string
  errorText: string
  dotClass: string
  fileName: string
  createdAt: number
  checked: boolean
}

function formatTime(ts: number): string {
  const d = new Date(ts)
  return `${`${d.getHours()}`.padStart(2, '0')}:${`${d.getMinutes()}`.padStart(2, '0')}`
}

function kindIcon(mediaType: QueueItem['mediaType']): string {
  if (mediaType === 'video') return Icon.videoWhite
  if (mediaType === 'audio') return Icon.micWhite
  return Icon.imageWhite
}

function readCols(): number {
  const v = wx.getStorageSync(KEY_COLS)
  return v === 2 || v === 3 || v === 4 ? v : 3
}

function readView(): 'grid' | 'list' {
  return wx.getStorageSync(KEY_VIEW) === 'list' ? 'list' : 'grid'
}

Page({
  data: {
    Icon,
    metrics: {} as Metrics,
    scrollTop: 0,
    viewingId: '',
    viewingName: '',
    projects: [] as Array<{ id: string; name: string }>,
    tally: { uploading: 0, failed: 0, staged: 0, landed: 0 } as Tally,
    days: [] as Array<{ key: string; title: string; items: Cell[] }>,
    cols: 3,
    view: 'grid' as 'grid' | 'list',
    selecting: false,
    selectedCount: 0,
  },

  unsubscribe: null as (() => void) | null,
  pollTimer: null as number | null,
  selected: new Set<string>(),

  onLoad() {
    const app = getApp<AppGlobal>()
    this.setData({ metrics: app.globalData.metrics, cols: readCols(), view: readView() })
  },

  onShow() {
    this.refresh()
    if (!this.unsubscribe) this.unsubscribe = subscribe(() => this.refresh())
    this.pollTimer = setInterval(() => pollStatus(), POLL_INTERVAL)
  },

  onHide() {
    if (this.pollTimer !== null) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  },

  onUnload() {
    this.onHide()
    if (this.unsubscribe) {
      this.unsubscribe()
      this.unsubscribe = null
    }
  },

  onPageScroll(e: { scrollTop: number }) {
    const crossed = e.scrollTop > 4
    if (crossed !== this.data.scrollTop > 4) this.setData({ scrollTop: e.scrollTop })
  },

  refresh() {
    const current = getSelectedProject()
    if (!current) return
    const projects = projectsIn(listItems(), current)
    const viewingId = projects.some((p) => p.id === this.data.viewingId)
      ? this.data.viewingId
      : projects[0].id
    const viewingName = projects.find((p) => p.id === viewingId)!.name
    const items = listItems(viewingId)
    const cells: Cell[] = items.map((it) => ({
      clientMediaId: it.clientMediaId,
      thumb: thumbFor(it),
      kindIcon: kindIcon(it.mediaType),
      time: formatTime(it.createdAt),
      statusText: stateText(it.state),
      errorText: it.state === 'failed' ? it.errorMessage || '' : '',
      dotClass: dotClass(it.state),
      fileName: it.fileName,
      createdAt: it.createdAt,
      checked: this.selected.has(it.clientMediaId),
    }))
    this.setData({
      projects, viewingId, viewingName,
      tally: tallyOf(items),
      days: groupByDay(cells),
      selectedCount: this.selected.size,
    })
  },

  // ---------- 切换看的项目 ----------

  onTitleTap() {
    const names = this.data.projects.map((p) => p.name)
    if (names.length <= 1) return
    wx.showActionSheet({
      itemList: names.slice(0, 6),
      success: (res) => {
        this.selected.clear()
        this.setData({ viewingId: this.data.projects[res.tapIndex].id, selecting: false })
        this.refresh()
      },
    })
  },

  // ---------- 列数 / 视图 ----------

  onToggleCols() {
    const cols = this.data.cols >= 4 ? 2 : this.data.cols + 1
    wx.setStorageSync(KEY_COLS, cols)
    this.setData({ cols })
  },

  onToggleView() {
    const view = this.data.view === 'grid' ? 'list' : 'grid'
    wx.setStorageSync(KEY_VIEW, view)
    this.setData({ view })
  },

  // ---------- 多选删除 ----------

  onToggleSelecting() {
    this.selected.clear()
    this.setData({ selecting: !this.data.selecting })
    this.refresh()
  },

  onTapCell(e: WechatMiniprogram.BaseEvent<WechatMiniprogram.IAnyObject, { id: string }>) {
    if (!this.data.selecting) return
    const id = e.currentTarget.dataset.id
    if (this.selected.has(id)) this.selected.delete(id)
    else this.selected.add(id)
    this.refresh()
  },

  onDelete() {
    if (this.selected.size === 0) return
    const ids = Array.from(this.selected)
    const states = listItems(this.data.viewingId)
      .filter((it) => this.selected.has(it.clientMediaId))
      .map((it) => it.state)
    wx.showModal({
      title: `删除 ${ids.length} 件`,
      content: deleteWarning(states),
      confirmText: '删除',
      confirmColor: '#B91C1C',
      success: (res) => {
        if (!res.confirm) return
        removeItems(ids)
        this.selected.clear()
        this.setData({ selecting: false })
        this.refresh()
      },
    })
  },

  onThumbError(e: WechatMiniprogram.BaseEvent<WechatMiniprogram.IAnyObject, { id: string }>) {
    markThumbBroken(e.currentTarget.dataset.id)
    this.refresh()
  },
})
```

- [ ] **Step 3: gallery.wxml**

```xml
<!-- 图集（D7 深色）。标题 = 正在看的项目，点标题切换；右侧：列数 / 视图 / 选择。 -->
<nav-bar title="{{viewingName}}" subtitle="{{projects.length > 1 ? '点标题切换项目' : ''}}" show-back="{{true}}" scroll-top="{{scrollTop}}" bind:titletap="onTitleTap">
  <view slot="action" class="tools">
    <view wx:if="{{view === 'grid' && !selecting}}" class="tools__btn tappable" bindtap="onToggleCols" aria-label="{{cols}} 列，切换列数">
      <text class="tools__cols mono">{{cols}}</text>
    </view>
    <view wx:if="{{!selecting}}" class="tools__btn tappable" bindtap="onToggleView" aria-label="{{view === 'grid' ? '切换到列表' : '切换到网格'}}">
      <text class="tools__text">{{view === 'grid' ? '列表' : '网格'}}</text>
    </view>
    <view class="tools__btn tappable" bindtap="onToggleSelecting">
      <text class="tools__text">{{selecting ? '取消' : '选择'}}</text>
    </view>
  </view>
</nav-bar>

<view class="page" style="padding-bottom: {{metrics.bottomInset + 96}}px;">
  <view class="tally">
    <text class="tally__num mono tally__num--waiting">{{tally.uploading}}</text><text class="tally__label">上传中</text>
    <text wx:if="{{tally.failed > 0}}" class="tally__failed">含 {{tally.failed}} 失败</text>
    <text class="tally__num mono tally__num--moving">{{tally.staged}}</text><text class="tally__label">已暂存</text>
    <text class="tally__num mono tally__num--arrived">{{tally.landed}}</text><text class="tally__label">已落盘</text>
  </view>

  <view class="status" wx:if="{{!days.length}}">
    <text class="status__text">这个项目还没有影像</text>
  </view>

  <block wx:for="{{days}}" wx:for-item="day" wx:key="key">
    <view class="day"><text class="label day__title">{{day.title}}</text></view>

    <!-- 网格 -->
    <view wx:if="{{view === 'grid'}}" class="grid grid--{{cols}}">
      <view
        class="cell tappable {{item.checked ? 'cell--checked' : ''}}"
        wx:for="{{day.items}}"
        wx:key="clientMediaId"
        data-id="{{item.clientMediaId}}"
        bindtap="onTapCell"
      >
        <image wx:if="{{item.thumb}}" class="cell__img" src="{{item.thumb}}" mode="aspectFill" data-id="{{item.clientMediaId}}" binderror="onThumbError" />
        <view wx:else class="cell__ph"><image class="cell__icon" src="{{item.kindIcon}}" mode="aspectFit" /></view>
        <view class="cell__dot {{item.dotClass}}"></view>
        <text class="cell__time mono">{{item.time}}</text>
        <view wx:if="{{selecting}}" class="cell__check {{item.checked ? 'cell__check--on' : ''}}"></view>
      </view>
    </view>

    <!-- 列表 -->
    <view wx:else class="list">
      <view
        class="row tappable"
        wx:for="{{day.items}}"
        wx:key="clientMediaId"
        data-id="{{item.clientMediaId}}"
        bindtap="onTapCell"
      >
        <view wx:if="{{selecting}}" class="row__check {{item.checked ? 'row__check--on' : ''}}"></view>
        <view class="row__thumb">
          <image wx:if="{{item.thumb}}" class="cell__img" src="{{item.thumb}}" mode="aspectFill" data-id="{{item.clientMediaId}}" binderror="onThumbError" />
          <view wx:else class="cell__ph"><image class="cell__icon" src="{{item.kindIcon}}" mode="aspectFit" /></view>
        </view>
        <view class="row__body">
          <view class="row__line"><view class="row__dot {{item.dotClass}}"></view><text class="row__status">{{item.statusText}}</text><text class="row__time mono">{{item.time}}</text></view>
          <text wx:if="{{item.errorText}}" class="row__error">{{item.errorText}}</text>
          <text class="row__name">{{item.fileName}}</text>
        </view>
      </view>
    </view>
  </block>
</view>

<!-- 底座：选择态显示删除 -->
<view wx:if="{{selecting}}" class="dock" style="padding-bottom: {{metrics.bottomInset + 16}}px;">
  <text class="dock__text">{{selectedCount ? '已选 ' + selectedCount + ' 件' : '点选要删除的影像'}}</text>
  <view class="dock__delete tappable {{selectedCount ? '' : 'dock__delete--off'}}" bindtap="onDelete">
    <text>删除 {{selectedCount}} 件</text>
  </view>
</view>
```

- [ ] **Step 4: gallery.wxss**

```css
/* 图集。D7：影像浏览走深色。影像铺满，分区靠日期小标签与发丝线；状态色只做小圆点。 */
page { background: var(--dk-bg); }

.page { background: var(--dk-bg); min-height: 100vh; }

.tools { display: flex; align-items: center; }
.tools__btn { min-width: var(--touch-min); height: var(--touch-min); padding: 0 var(--s2); }
.tools__text { font-size: var(--t-small); color: var(--dk-fg); }
.tools__cols { font-size: var(--t-small); color: var(--dk-fg); }

.tally {
  display: flex;
  align-items: baseline;
  gap: 4rpx;
  padding: var(--s2) var(--gutter) var(--s3);
}
.tally__num { font-size: var(--t-small); font-weight: 500; margin-left: var(--s3); }
.tally__num:first-child { margin-left: 0; }
.tally__num--waiting { color: #F97316; }
.tally__num--moving  { color: #60A5FA; }
.tally__num--arrived { color: #4ADE80; }
.tally__label { font-size: var(--t-nano); color: var(--dk-fg-muted); }
.tally__failed { font-size: var(--t-nano); color: var(--st-failed); margin-left: var(--s1); }

.status { padding: var(--s16) var(--gutter) 0; }
.status__text { font-size: var(--t-small); color: var(--dk-fg-muted); }

.day { padding: var(--s4) var(--gutter) var(--s2); }
.day__title { color: rgba(255, 255, 255, 0.6); }

/* ---- 网格 ---- */
.grid { display: grid; gap: 3rpx; }
.grid--2 { grid-template-columns: repeat(2, 1fr); }
.grid--3 { grid-template-columns: repeat(3, 1fr); }
.grid--4 { grid-template-columns: repeat(4, 1fr); }

.cell { position: relative; aspect-ratio: 1; overflow: hidden; background: var(--dk-surface); }
.cell__img { width: 100%; height: 100%; display: block; }
.cell__ph { width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; }
.cell__icon { width: 40rpx; height: 40rpx; opacity: 0.5; }
.cell__dot {
  position: absolute; top: 12rpx; right: 12rpx;
  width: 12rpx; height: 12rpx; border-radius: 50%;
}
.cell__time {
  position: absolute; left: 12rpx; bottom: 10rpx;
  font-size: var(--t-nano); color: rgba(255, 255, 255, 0.5); letter-spacing: 0.04em;
}
.cell__check {
  position: absolute; top: 12rpx; left: 12rpx;
  width: 36rpx; height: 36rpx; border-radius: 50%;
  border: 3rpx solid rgba(255, 255, 255, 0.85);
}
.cell__check--on { background: #60A5FA; border-color: #60A5FA; }
.cell--checked::after {
  content: ''; position: absolute; inset: 0; background: rgba(0, 0, 0, 0.35);
}

.dot--waiting { background: #F97316; }
.dot--moving  { background: #60A5FA; }
.dot--arrived { background: #4ADE80; }
.dot--failed  { background: var(--st-failed); }

/* ---- 列表 ---- */
.list { padding: 0 var(--gutter); }
.row {
  display: flex; align-items: flex-start; gap: var(--s3);
  padding: var(--s3) 0; border-bottom: 1rpx solid var(--dk-rule);
  justify-content: flex-start;
}
.row__check {
  flex-shrink: 0; margin-top: var(--s2);
  width: 36rpx; height: 36rpx; border-radius: 50%;
  border: 3rpx solid rgba(255, 255, 255, 0.5);
}
.row__check--on { background: #60A5FA; border-color: #60A5FA; }
.row__thumb { width: 88rpx; height: 88rpx; flex-shrink: 0; overflow: hidden; background: var(--dk-surface); }
.row__body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 4rpx; }
.row__line { display: flex; align-items: center; gap: var(--s1); }
.row__dot { width: 10rpx; height: 10rpx; border-radius: 50%; }
.row__status { font-size: var(--t-small); color: var(--dk-fg); }
.row__time { font-size: var(--t-micro); color: var(--dk-fg-muted); }
.row__error { font-size: var(--t-nano); color: var(--st-failed); line-height: 1.5; }
.row__name { font-size: var(--t-nano); color: var(--dk-fg-muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

/* ---- 底座 ---- */
.dock {
  position: fixed; left: 0; right: 0; bottom: 0;
  display: flex; align-items: center; justify-content: space-between;
  padding: var(--s3) var(--gutter);
  background: linear-gradient(to bottom, rgba(10, 11, 13, 0), rgba(10, 11, 13, 0.94) 40%);
}
.dock__text { font-size: var(--t-small); color: var(--dk-fg-muted); }
.dock__delete {
  padding: 0 var(--s4); height: var(--touch-min);
  background: var(--st-failed); color: #fff; font-size: var(--t-small);
}
.dock__delete--off { opacity: 0.4; }
```

- [ ] **Step 5: app.json pages 加 `"pages/gallery/gallery"`**

- [ ] **Step 6: `npm run typecheck`、`npm test` 通过；微信开发者工具走查**：`npm run shot` 需 IDE 服务端口；若不可用，至少 typecheck 过并在 IDE 里打开 gallery 页目视：项目切换、列数、列表、多选删除弹窗文案。

- [ ] **Step 7: 提交**

```bash
git add miniprogram/pages/gallery miniprogram/app.json
git commit -m "feat(miniprogram): 图集页——按项目看、按日分段、列数/视图/多选删除（dev-board#385/#386）"
```

---

### Task 10: 收尾——文档、PR、看板

- [ ] **Step 1: README 目录段** `pages/` 下补一行 `gallery/  图集（按项目看、按日分段、删除）`；README「数据流」末行「手机端标记『已抵达』」改为「手机端标记『已落盘』」。
- [ ] **Step 2: `npm run typecheck && npm test`、iOS 单测与 Debug 构建全绿。**
- [ ] **Step 3: 推分支、开 PR**（标题 `feat: 图集按项目分组 + 传输三态 + 图集工具（iOS + 小程序，dev-board#383-386）`，正文列四张卡与自验证，末尾 `🤖 Generated with [Claude Code](https://claude.com/claude-code)`）。
- [ ] **Step 4: 四张卡评论落实记录，状态改「待复测」。**
