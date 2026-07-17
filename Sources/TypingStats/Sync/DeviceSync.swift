import Foundation
import os.log

private let syncLogger = Logger(subsystem: "com.jinduoxia.TypingStats", category: "sync")

/// A stable per-device identity so each Mac owns exactly one snapshot file.
enum DeviceIdentity {
    private static let idKey = "deviceId"

    static let id: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: idKey) { return existing }
        let new = UUID().uuidString
        defaults.set(new, forKey: idKey)
        return new
    }()

    static var name: String {
        Host.current().localizedName ?? "Mac"
    }
}

// MARK: - Snapshot model (what each device writes to iCloud)

struct AppSnapshot: Codable {
    var name: String
    var keystrokes: Int
}

struct DaySnapshot: Codable {
    var keystrokes: Int
    var apps: [String: AppSnapshot]   // bundleId → per-app counts
}

struct DeviceSnapshot: Codable {
    var deviceId: String
    var deviceName: String
    var updatedAt: Double             // epoch seconds
    var days: [String: DaySnapshot]   // "yyyy-MM-dd" → totals
}

/// A row in the Settings → 同步 device list.
struct SyncedDeviceInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let updatedAt: Date
    let todayKeystrokes: Int
    let isSelf: Bool
}

/// Reads/writes per-device snapshot files in the shared iCloud Drive folder.
///
/// No iCloud entitlement or paid account is needed: a non-sandboxed app can write
/// into the user's iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs`)
/// like any folder, and iCloud syncs those files across the user's Macs. Each
/// device writes only its own `<deviceId>.json`, so there are never write
/// conflicts; the merged view sums this device's live DB with the others' files.
/// `@unchecked Sendable`: holds no mutable state — only immutable `let`s doing
/// thread-safe file (NSFileCoordinator) and DB (GRDB DatabaseQueue) I/O — so it's
/// safe to hand to the background sync queue.
final class CloudSyncStore: @unchecked Sendable {
    static let folderName = "TypingStats"

    /// Snapshots carry only this many recent days, so their size (and the cost
    /// of encoding/decoding them every sync pass) stays bounded no matter how
    /// long the app has been collecting history. Older days remain in each
    /// device's local DB; only the cross-device merged view is limited.
    static let syncedDayCount = 365

    private let fm = FileManager.default
    private let stats = StatsService()

    /// Decoded snapshots keyed by file path, reused until the file's
    /// modification date changes — CloudSyncStore instances are created per
    /// refresh, so the cache is shared. Other devices rewrite their file every
    /// ~5 minutes while we re-read every 20 seconds; without this, each pass
    /// re-decodes every device's full snapshot.
    private struct CachedSnapshot {
        let modified: Date
        let snapshot: DeviceSnapshot
    }
    private static var snapshotCache: [String: CachedSnapshot] = [:]
    private static let cacheLock = NSLock()
    private static let maxCachedSnapshotCount = 16

    /// The shared folder, or nil when iCloud Drive is turned off.
    var folder: URL? {
        let base = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard fm.fileExists(atPath: base.path) else { return nil }
        return base.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    var isAvailable: Bool { folder != nil }

    func ensureFolder() {
        guard let folder else { return }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: Writing our own snapshot

    /// Serialize this device's full history (from the local DB) to its file.
    func writeOwnSnapshot() {
        guard let folder else { return }
        ensureFolder()
        guard let snapshot = buildOwnSnapshot() else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let url = folder.appendingPathComponent("\(DeviceIdentity.id).json")
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
            do { try data.write(to: u, options: .atomic) }
            catch { syncLogger.error("write snapshot failed: \(error.localizedDescription, privacy: .public)") }
        }
        if let coordError { syncLogger.error("coordinate write failed: \(coordError.localizedDescription, privacy: .public)") }
    }

    private func buildOwnSnapshot() -> DeviceSnapshot? {
        let cal = Calendar(identifier: .gregorian)
        let cutoffDate = cal.date(byAdding: .day, value: -(Self.syncedDayCount - 1), to: Date()) ?? Date()
        let cutoff = StatsService.dateKey(for: cutoffDate)
        guard let history = try? stats.history(sinceKey: cutoff) else { return nil }

        var out: [String: DaySnapshot] = [:]
        for day in history.days {
            out[day.date] = DaySnapshot(keystrokes: day.keystrokes, apps: [:])
        }
        for a in history.apps {
            out[a.date, default: DaySnapshot(keystrokes: 0, apps: [:])]
                .apps[a.bundleId] = AppSnapshot(name: a.appName, keystrokes: a.keystrokes)
        }
        return DeviceSnapshot(
            deviceId: DeviceIdentity.id,
            deviceName: DeviceIdentity.name,
            updatedAt: Date().timeIntervalSince1970,
            days: out
        )
    }

    // MARK: Reading other devices

    /// All snapshots except this device's. Triggers download of any not-yet-local
    /// iCloud placeholders so they're readable on the next pass.
    func otherSnapshots() -> [DeviceSnapshot] {
        guard let folder else {
            Self.pruneSnapshotCache(validPaths: [])
            return []
        }
        guard let items = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        let ownFileName = "\(DeviceIdentity.id).json"
        let snapshotFiles = items.filter {
            $0.pathExtension == "json"
                && !$0.lastPathComponent.hasPrefix(".")
                && $0.lastPathComponent != ownFileName
        }
        Self.pruneSnapshotCache(validPaths: Set(snapshotFiles.map(\.path)))

        var result: [DeviceSnapshot] = []
        for item in items {
            // Not-yet-downloaded files appear as hidden ".name.icloud" placeholders.
            if item.pathExtension == "icloud" || item.lastPathComponent.hasPrefix(".") {
                try? fm.startDownloadingUbiquitousItem(at: item)
                continue
            }
            guard item.pathExtension == "json" else { continue }
            guard item.lastPathComponent != ownFileName else { continue }

            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let snap: DeviceSnapshot
            if let cached = Self.cachedSnapshot(path: item.path, modified: modified) {
                snap = cached
            } else {
                var data: Data?
                var coordError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: item, options: [], error: &coordError) { u in
                    data = try? Data(contentsOf: u)
                }
                guard let data, let decoded = try? JSONDecoder().decode(DeviceSnapshot.self, from: data) else { continue }
                Self.storeSnapshot(decoded, path: item.path, modified: modified)
                snap = decoded
            }
            if snap.deviceId == DeviceIdentity.id { continue }   // our own file: use the live DB instead
            result.append(snap)
        }
        return result
    }

    private static func cachedSnapshot(path: String, modified: Date) -> DeviceSnapshot? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cached = snapshotCache[path], cached.modified == modified, modified != .distantPast else {
            return nil
        }
        return cached.snapshot
    }

    private static func storeSnapshot(_ snapshot: DeviceSnapshot, path: String, modified: Date) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        snapshotCache[path] = CachedSnapshot(modified: modified, snapshot: snapshot)
        if snapshotCache.count > maxCachedSnapshotCount,
           let oldestPath = snapshotCache.min(by: { $0.value.modified < $1.value.modified })?.key {
            snapshotCache.removeValue(forKey: oldestPath)
        }
    }

    private static func pruneSnapshotCache(validPaths: Set<String>) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        snapshotCache = snapshotCache.filter { validPaths.contains($0.key) }
    }
}
