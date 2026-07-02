import Foundation
import GRDB

/// Query layer above DatabaseManager — UI talks to this.
struct StatsService {
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

    /// All per-app rows for a given day (unlimited) — used to build the cloud
    /// sync snapshot.
    func allApps(onKey key: String) throws -> [AppStat] {
        try db.dbQueue.read { db in
            try AppStat.filter(Column("date") == key).fetchAll(db)
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
        try db.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO daily_stat (date, keystrokes) VALUES (?, ?)
                ON CONFLICT(date) DO UPDATE SET keystrokes = keystrokes + excluded.keystrokes
                """, arguments: [key, total])

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

    static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}

/// Coalesces per-keystroke writes on a background queue: keystrokes are tallied
/// in memory and flushed to SQLite every couple of seconds, so fast typing never
/// turns into a storm of tiny transactions. Order is irrelevant (commutative).
final class KeystrokeRecorder {
    private let service: StatsService
    private let queue = DispatchQueue(label: "com.jinduoxia.TypingStats.dbwrite", qos: .utility)
    private let flushInterval: TimeInterval = 2.0

    private var pendingTotal = 0
    private var pendingApps: [String: (name: String, count: Int)] = [:]
    private var flushScheduled = false

    init(service: StatsService = StatsService()) {
        self.service = service
    }

    func record(app: FrontmostApp?) {
        queue.async {
            self.pendingTotal += 1
            if let app {
                let prev = self.pendingApps[app.bundleId]?.count ?? 0
                self.pendingApps[app.bundleId] = (app.name, prev + 1)
            }
            self.scheduleFlush()
        }
    }

    /// Force any buffered keystrokes to disk now (e.g. before the app quits).
    func flushNow() {
        queue.async { self.flush() }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + flushInterval) { self.flush() }
    }

    private func flush() {
        flushScheduled = false
        let total = pendingTotal
        let apps = pendingApps
        pendingTotal = 0
        pendingApps = [:]
        guard total > 0 else { return }
        try? service.recordKeystrokes(total: total, apps: apps)
    }
}
