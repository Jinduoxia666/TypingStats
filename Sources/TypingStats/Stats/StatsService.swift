import Foundation
import GRDB

/// Query layer above DatabaseManager — UI talks to this.
struct StatsService: Sendable {
    let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    func todayStats() throws -> DailyStat {
        let today = Self.dateKey(for: Date())
        return try db.dbQueue.read { db in
            try DailyStat.fetchOne(db, key: today) ?? DailyStat(date: today)
        }
    }

    func recentDays(_ count: Int) throws -> [DailyStat] {
        try db.dbQueue.read { db in
            try DailyStat
                .order(Column("date").desc)
                .limit(count)
                .fetchAll(db)
        }
    }

    /// All daily rows ascending by date — for export.
    func allDays() throws -> [DailyStat] {
        try db.dbQueue.read { db in
            try DailyStat.order(Column("date")).fetchAll(db)
        }
    }

    /// All per-app rows for a given day (unlimited).
    func allApps(onKey key: String) throws -> [AppStat] {
        try db.dbQueue.read { db in
            try AppStat.filter(Column("date") == key).fetchAll(db)
        }
    }

    /// Per-hour totals for a given day, hour → keystrokes (missing hours absent).
    func hours(onKey key: String) throws -> [Int: Int] {
        try db.dbQueue.read { db in
            let rows = try HourStat.filter(Column("date") == key).fetchAll(db)
            return Dictionary(rows.map { ($0.hour, $0.keystrokes) }, uniquingKeysWith: +)
        }
    }

    /// Daily totals, per-app and per-hour rows for the sync snapshot, fetched in
    /// a single read (no per-day query storm). Hourly rows get their own, much
    /// nearer cutoff: they are ~24 rows per day and only the current day's are
    /// ever read back, so carrying the full `key` range would bloat every
    /// snapshot rewrite for nothing.
    func history(sinceKey key: String, hoursSinceKey hourKey: String) throws
        -> (days: [DailyStat], apps: [AppStat], hours: [HourStat]) {
        try db.dbQueue.read { db in
            let days = try DailyStat.filter(Column("date") >= key).fetchAll(db)
            let apps = try AppStat.filter(Column("date") >= key).fetchAll(db)
            let hours = try HourStat.filter(Column("date") >= hourKey).fetchAll(db)
            return (days, apps, hours)
        }
    }

    /// Top apps for a given day, ranked by keystrokes.
    func topApps(on date: Date = Date(), limit: Int = 10) throws -> [AppStat] {
        let key = Self.dateKey(for: date)
        return try db.dbQueue.read { db in
            try AppStat
                .filter(Column("date") == key)
                .order(Column("keystrokes").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Distinct apps that have ever recorded keystrokes, busiest first — drives
    /// the "exclude apps" settings list.
    func knownApps() throws -> [(bundleId: String, name: String)] {
        try db.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT bundle_id, app_name, SUM(keystrokes) AS total
                FROM app_stat
                GROUP BY bundle_id
                ORDER BY total DESC
                """).map { (bundleId: $0["bundle_id"], name: $0["app_name"]) }
        }
    }

    /// Name of the busiest app on a given day (for the export's "Top app" column).
    func topAppName(onKey key: String) throws -> String? {
        try db.dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT app_name FROM app_stat WHERE date = ?
                ORDER BY keystrokes DESC LIMIT 1
                """, arguments: [key])
        }
    }

    // MARK: - Mutations
    //
    // Additive UPSERTs (`+= excluded.*`), so they're commutative — concurrent /
    // out-of-order / coalesced writes still produce correct totals.

    /// Adds a batch of keystrokes to today's total and the per-app breakdown, in
    /// a single transaction. `apps` maps bundleId → (display name, count).
    func recordKeystrokes(
        total: Int,
        apps: [String: (name: String, count: Int)],
        date: Date = Date()
    ) throws {
        guard total > 0 else { return }
        let key = Self.dateKey(for: date)
        let hour = Self.hourKey(for: date)
        try db.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO daily_stat (date, keystrokes) VALUES (?, ?)
                ON CONFLICT(date) DO UPDATE SET keystrokes = keystrokes + excluded.keystrokes
                """, arguments: [key, total])

            try db.execute(sql: """
                INSERT INTO hour_stat (date, hour, keystrokes) VALUES (?, ?, ?)
                ON CONFLICT(date, hour) DO UPDATE SET keystrokes = keystrokes + excluded.keystrokes
                """, arguments: [key, hour, total])

            for (bundleId, info) in apps {
                try db.execute(sql: """
                    INSERT INTO app_stat (date, bundle_id, app_name, keystrokes)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(date, bundle_id) DO UPDATE SET
                      keystrokes = keystrokes + excluded.keystrokes,
                      app_name = excluded.app_name
                    """, arguments: [key, bundleId, info.name, info.count])
            }
        }
    }

    /// Shared formatter: DateFormatter construction is expensive (ICU init) and
    /// this runs on hot paths. `string(from:)` is thread-safe on macOS 10.9+.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func dateKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Local-timezone hour (0...23) a batch of keystrokes belongs to.
    static func hourKey(for date: Date) -> Int {
        hourCalendar.component(.hour, from: date)
    }

    private static let hourCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()
}

/// Coalesces per-keystroke writes on a background queue: keystrokes are tallied
/// in memory and flushed to SQLite every couple of seconds, so fast typing never
/// turns into a storm of tiny transactions. Order is irrelevant (commutative).
@MainActor
final class KeystrokeRecorder {
    private let service: StatsService
    private let writeQueue = DispatchQueue(label: "com.jinduoxia.TypingStats.dbwrite", qos: .utility)
    private let flushInterval: TimeInterval = 2.0

    private var pendingTotal = 0
    private var pendingApps: [String: (name: String, count: Int)] = [:]
    private var flushTask: Task<Void, Never>?

    init(service: StatsService = StatsService()) {
        self.service = service
    }

    func record(app: FrontmostApp?) {
        pendingTotal += 1
        if let app {
            let prev = pendingApps[app.bundleId]?.count ?? 0
            pendingApps[app.bundleId] = (app.name, prev + 1)
        }
        scheduleFlush()
    }

    /// Force any buffered keystrokes to disk now (e.g. before the app quits).
    func flushNow() {
        flushTask?.cancel()
        flushTask = nil
        flush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let delay = UInt64(flushInterval * 1_000_000_000)
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        flushTask = nil
        let total = pendingTotal
        let apps = pendingApps
        let date = Date()
        pendingTotal = 0
        pendingApps = [:]
        guard total > 0 else { return }
        let service = self.service
        writeQueue.async {
            try? service.recordKeystrokes(total: total, apps: apps, date: date)
        }
    }
}
