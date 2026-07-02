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
struct SyncedDeviceInfo: Identifiable {
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

    private let fm = FileManager.default
    private let stats = StatsService()

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
        guard let days = try? stats.allDays() else { return nil }
        var out: [String: DaySnapshot] = [:]
        for day in days {
            let apps = (try? stats.allApps(onKey: day.date)) ?? []
            var appMap: [String: AppSnapshot] = [:]
            for a in apps { appMap[a.bundleId] = AppSnapshot(name: a.appName, keystrokes: a.keystrokes) }
            out[day.date] = DaySnapshot(keystrokes: day.keystrokes, apps: appMap)
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
        guard let folder,
              let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }

        var result: [DeviceSnapshot] = []
        for item in items {
            // Not-yet-downloaded files appear as hidden ".name.icloud" placeholders.
            if item.pathExtension == "icloud" || item.lastPathComponent.hasPrefix(".") {
                try? fm.startDownloadingUbiquitousItem(at: item)
                continue
            }
            guard item.pathExtension == "json" else { continue }

            var data: Data?
            var coordError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: item, options: [], error: &coordError) { u in
                data = try? Data(contentsOf: u)
            }
            guard let data, let snap = try? JSONDecoder().decode(DeviceSnapshot.self, from: data) else { continue }
            if snap.deviceId == DeviceIdentity.id { continue }   // our own file: use the live DB instead
            result.append(snap)
        }
        return result
    }
}
