import Foundation
import GRDB

/// Owns the SQLite database connection pool and runs migrations on init.
/// Stored under Application Support / TypingStats / typingstats.sqlite.
/// GRDB's DatabaseQueue serializes its connection access and is safe to share
/// with the recorder's background write queue.
final class DatabaseManager: @unchecked Sendable {
    static let shared = try! DatabaseManager()

    let dbQueue: DatabaseQueue

    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("TypingStats", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("typingstats.sqlite").path

        var config = Configuration()
        config.label = "TypingStats.db"
        self.dbQueue = try DatabaseQueue(path: path, configuration: config)
        try Migrations.run(on: dbQueue)
    }
}

enum Migrations {
    static func run(on dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "daily_stat") { t in
                t.column("date", .text).primaryKey()       // YYYY-MM-DD, local tz
                t.column("cjk_chars", .integer).notNull().defaults(to: 0)
                t.column("english_words", .integer).notNull().defaults(to: 0)
                t.column("other_chars", .integer).notNull().defaults(to: 0)
                t.column("deletes", .integer).notNull().defaults(to: 0)
                t.column("active_seconds", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "app_stat") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull().indexed()
                t.column("bundle_id", .text).notNull().indexed()
                t.column("app_name", .text).notNull()
                t.column("cjk_chars", .integer).notNull().defaults(to: 0)
                t.column("english_words", .integer).notNull().defaults(to: 0)
                t.column("other_chars", .integer).notNull().defaults(to: 0)
                t.uniqueKey(["date", "bundle_id"])
            }

            try db.create(table: "paste_event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull().indexed()
                t.column("bundle_id", .text)
                t.column("char_count", .integer).notNull()
                t.column("created_at", .datetime).notNull()
            }
        }

        // The app now counts keystrokes rather than classified characters.
        // Add a keystroke tally to the daily and per-app tables; the legacy
        // character columns are left in place (harmless, defaulted) so old
        // databases migrate without data loss.
        migrator.registerMigration("v2_keystrokes") { db in
            try db.alter(table: "daily_stat") { t in
                t.add(column: "keystrokes", .integer).notNull().defaults(to: 0)
            }
            try db.alter(table: "app_stat") { t in
                t.add(column: "keystrokes", .integer).notNull().defaults(to: 0)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
