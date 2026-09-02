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

    /// 删除确认等级：按所选里最坏的桶说话。n = 该桶件数；landed 时 n = 总数。
    static func deleteWarningLevel(_ states: [TransferState]) -> (level: String, n: Int) {
        for phase in ContractStates.deleteWarnOrder where phase != "landed" {
            let n = states.filter { $0.phase.rawValue == phase }.count
            if n > 0 { return (ContractStates.deleteWarnLevel[phase]!, n) }
        }
        return ("landed", states.count)
    }

    static func deleteWarning(for items: [CaptureItem]) -> String {
        let (level, n) = deleteWarningLevel(items.map(\.state))
        return tr(ContractStates.deleteWarnKey[level]!, ["n": String(n)])
    }
}
