import Foundation

/// Where a job's definition lives. Jobs the user wrote themselves sort first —
/// the several hundred Apple agents are noise most of the time.
enum LaunchdJobSource: Int, CaseIterable, Comparable {
    case user
    case global
    case system
    /// Registered in the user domain but without a plist in the three agent
    /// directories: XPC services shipped inside app bundles, mostly.
    case unmanaged

    var title: String {
        switch self {
        case .user: return "用户"
        case .global: return "全局"
        case .system: return "系统"
        case .unmanaged: return "其他"
        }
    }

    var directoryURL: URL? {
        switch self {
        case .user:
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        case .global:
            return URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)
        case .system:
            return URL(fileURLWithPath: "/System/Library/LaunchAgents", isDirectory: true)
        case .unmanaged:
            return nil
        }
    }

    static func < (lhs: LaunchdJobSource, rhs: LaunchdJobSource) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One `StartCalendarInterval` entry. Every field is optional; launchd treats a
/// missing field as "any value".
struct LaunchdCalendarInterval: Equatable {
    var minute: Int?
    var hour: Int?
    var day: Int?
    var weekday: Int?
    var month: Int?

    init(minute: Int? = nil, hour: Int? = nil, day: Int? = nil, weekday: Int? = nil, month: Int? = nil) {
        self.minute = minute
        self.hour = hour
        self.day = day
        self.weekday = weekday
        self.month = month
    }

    init?(plist: [String: Any]) {
        func value(_ key: String) -> Int? {
            (plist[key] as? NSNumber)?.intValue
        }
        self.init(
            minute: value("Minute"),
            hour: value("Hour"),
            day: value("Day"),
            weekday: value("Weekday"),
            month: value("Month")
        )
        if minute == nil, hour == nil, day == nil, weekday == nil, month == nil { return nil }
    }

    /// Components to match against the calendar.
    ///
    /// Fields finer than the coarsest one specified are pinned to their first
    /// value rather than left wildcard: `{Hour: 9}` means 9:00 every day, not
    /// every minute of the 9 o'clock hour. That is what launchd does in
    /// practice and what everyone writing these plists expects.
    ///
    /// `dayMatchesWeekday` picks which of the two mutually exclusive day rules
    /// to encode, since `DateComponents` matching ANDs its fields while launchd
    /// ORs `Day` and `Weekday`.
    func matchingComponents(useWeekday: Bool) -> DateComponents {
        var components = DateComponents()
        components.month = month
        if useWeekday {
            components.weekday = weekday.map { Self.calendarWeekday(fromLaunchd: $0) }
        } else {
            components.day = day
        }

        let hasCoarserThanHour = components.month != nil || components.day != nil || components.weekday != nil
        components.hour = hour ?? (hasCoarserThanHour ? 0 : nil)
        components.minute = minute ?? (components.hour != nil ? 0 : nil)
        components.second = 0
        return components
    }

    /// launchd counts Sunday as both 0 and 7; `Calendar` counts it as 1.
    static func calendarWeekday(fromLaunchd weekday: Int) -> Int {
        (((weekday % 7) + 7) % 7) + 1
    }

    var summary: String {
        let time = String(format: "%02d:%02d", hour ?? 0, minute ?? 0)
        var parts: [String] = []
        if let month {
            parts.append("每年 \(month) 月")
        }
        if let weekday {
            parts.append("每周\(Self.weekdayNames[Self.calendarWeekday(fromLaunchd: weekday) - 1])")
        }
        if let day {
            parts.append(month == nil ? "每月 \(day) 日" : "\(day) 日")
        }
        if parts.isEmpty {
            if hour != nil {
                parts.append("每天")
            } else if minute != nil {
                return "每小时第 \(minute ?? 0) 分"
            } else {
                return "每分钟"
            }
        }
        return parts.joined(separator: " ") + " " + time
    }

    private static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]
}

/// Everything in a job's plist that decides *when* it runs.
struct LaunchdSchedule: Equatable {
    var calendarIntervals: [LaunchdCalendarInterval] = []
    var startInterval: Int?
    var runAtLoad = false
    var keepAlive = false
    var watchPaths: [String] = []
    var queueDirectories: [String] = []
    var startOnMount = false
    var machServices: [String] = []
    var hasSockets = false

    init() {}

    init(plist: [String: Any]) {
        if let single = plist["StartCalendarInterval"] as? [String: Any],
           let interval = LaunchdCalendarInterval(plist: single) {
            calendarIntervals = [interval]
        } else if let many = plist["StartCalendarInterval"] as? [[String: Any]] {
            calendarIntervals = many.compactMap(LaunchdCalendarInterval.init(plist:))
        }
        startInterval = (plist["StartInterval"] as? NSNumber)?.intValue
        runAtLoad = (plist["RunAtLoad"] as? NSNumber)?.boolValue ?? false
        keepAlive = LaunchdSchedule.isKeepAliveEnabled(plist["KeepAlive"])
        watchPaths = plist["WatchPaths"] as? [String] ?? []
        queueDirectories = plist["QueueDirectories"] as? [String] ?? []
        startOnMount = (plist["StartOnMount"] as? NSNumber)?.boolValue ?? false
        machServices = (plist["MachServices"] as? [String: Any]).map { Array($0.keys).sorted() } ?? []
        hasSockets = plist["Sockets"] != nil
    }

    private static func isKeepAliveEnabled(_ value: Any?) -> Bool {
        if let flag = value as? NSNumber { return flag.boolValue }
        return value is [String: Any]
    }

    /// Human-readable trigger list, most specific first.
    var descriptions: [String] {
        var items = calendarIntervals.map(\.summary)
        if let startInterval {
            items.append("每隔 \(LaunchdSchedule.durationText(seconds: startInterval))")
        }
        if runAtLoad { items.append("加载时运行") }
        if keepAlive { items.append("保持常驻") }
        for path in watchPaths { items.append("监视路径 \(path)") }
        for path in queueDirectories { items.append("监视目录 \(path)") }
        if startOnMount { items.append("挂载新卷时") }
        if !machServices.isEmpty { items.append("按需(Mach 服务 \(machServices.count) 个)") }
        if hasSockets { items.append("按需(Socket)") }
        return items.isEmpty ? ["按需 / 未声明触发条件"] : items
    }

    /// Next wall-clock trigger, when it can be known exactly.
    ///
    /// Only `StartCalendarInterval` gives a fixed clock time. `StartInterval`
    /// counts from whenever launchd loaded the job and that instant is not
    /// exposed anywhere, so those jobs deliberately return `nil` rather than a
    /// made-up time — the interval itself is shown instead.
    func nextFireDate(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        calendarIntervals
            .compactMap { LaunchdSchedule.nextFireDate(for: $0, after: date, calendar: calendar) }
            .min()
    }

    static func nextFireDate(
        for interval: LaunchdCalendarInterval,
        after date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        // Day and Weekday are an OR in launchd, so each gets its own search and
        // the earlier match wins.
        var candidates: [DateComponents] = []
        if interval.weekday != nil {
            candidates.append(interval.matchingComponents(useWeekday: true))
        }
        if interval.day != nil || candidates.isEmpty {
            candidates.append(interval.matchingComponents(useWeekday: false))
        }

        return candidates.compactMap {
            calendar.nextDate(
                after: date,
                matching: $0,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        }.min()
    }

    static func durationText(seconds: Int) -> String {
        guard seconds > 0 else { return "\(seconds) 秒" }
        if seconds % 86_400 == 0 { return "\(seconds / 86_400) 天" }
        if seconds % 3_600 == 0 { return "\(seconds / 3_600) 小时" }
        if seconds % 60 == 0 { return "\(seconds / 60) 分钟" }
        return "\(seconds) 秒"
    }
}

/// A user-domain (`gui/$UID`) launchd job: what launchctl knows about it plus
/// whatever its plist says.
struct LaunchdJob: Identifiable, Equatable {
    let label: String
    let source: LaunchdJobSource
    let plistPath: String?
    let pid: Int?
    let lastExitStatus: Int?
    let isLoaded: Bool
    let isDisabled: Bool
    let schedule: LaunchdSchedule
    /// Top-level plist keys, formatted for display and sorted by key.
    let configuration: [LaunchdConfigEntry]
    let programSummary: String?
    var standardOutPath: String? = nil
    var standardErrorPath: String? = nil

    var id: String { label }

    /// The files launchd redirects this job's output into, deduped — most
    /// plists point stdout and stderr at the same file.
    var logPaths: [(path: String, roles: [String])] {
        var ordered: [String] = []
        var roles: [String: [String]] = [:]
        for (path, role) in [(standardOutPath, "标准输出"), (standardErrorPath, "标准错误")] {
            guard let path, !path.isEmpty else { continue }
            let expanded = (path as NSString).expandingTildeInPath
            if roles[expanded] == nil { ordered.append(expanded) }
            roles[expanded, default: []].append(role)
        }
        return ordered.map { ($0, roles[$0] ?? []) }
    }

    var statusText: String {
        if isDisabled { return "已停用" }
        if let pid { return "运行中 · PID \(pid)" }
        if isLoaded { return "已加载 · 未运行" }
        return "未加载"
    }

    func nextFireDate(after date: Date = Date()) -> Date? {
        guard !isDisabled else { return nil }
        return schedule.nextFireDate(after: date)
    }
}

struct LaunchdConfigEntry: Identifiable, Equatable {
    let key: String
    let value: String

    var id: String { key }
}
