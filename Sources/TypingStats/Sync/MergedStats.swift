import Foundation

/// Presents statistics merged across all of the user's devices: this device's
/// live local DB plus every other device's iCloud snapshot. Returns the same
/// `DailyStat` / `AppStat` shapes the UI already uses, so views just swap
/// `StatsService()` for `MergedStats()`.
///
/// Snapshots are read once at init (a handful of small files) and cached for the
/// lifetime of this instance — create a fresh `MergedStats` per UI refresh.
/// Today's app ranking for one device, used by the per-device app list.
struct DeviceAppStats: Identifiable {
    let id: String            // deviceId
    let deviceName: String
    let isSelf: Bool
    let apps: [AppStat]
}

struct DeviceDayStat: Identifiable {
    let date: String
    let deviceId: String
    let deviceName: String
    let isSelf: Bool
    let keystrokes: Int

    var id: String { "\(date)-\(deviceId)" }
}

struct DeviceDayBreakdown: Identifiable {
    let date: String
    let segments: [DeviceDayStat]

    var id: String { date }
    var totalKeystrokes: Int { segments.reduce(0) { $0 + $1.keystrokes } }
}

final class MergedStats {
    private let local = StatsService()
    private let others: [DeviceSnapshot]

    init(cloud: CloudSyncStore = CloudSyncStore()) {
        self.others = cloud.otherSnapshots()
    }

    /// Merged per-day totals for the last `count` calendar days, oldest→newest.
    func recentDays(_ count: Int) -> [DailyStat] {
        let keys = Self.lastDayKeys(count)
        var totals = [String: Int]()
        for key in keys { totals[key] = 0 }

        for day in (try? local.recentDays(count + 5)) ?? [] where totals[day.date] != nil {
            totals[day.date]! += day.keystrokes
        }
        for snap in others {
            for key in keys {
                if let day = snap.days[key] { totals[key]! += day.keystrokes }
            }
        }
        return keys.map { DailyStat(date: $0, keystrokes: totals[$0] ?? 0) }
    }

    /// Per-day totals split by device for stacked history charts.
    func recentDaysByDevice(_ count: Int) -> [DeviceDayBreakdown] {
        let keys = Self.lastDayKeys(count)
        let localDays = Dictionary(
            uniqueKeysWithValues: ((try? local.recentDays(count + 5)) ?? []).map { ($0.date, $0.keystrokes) }
        )

        return keys.map { key in
            var segments: [DeviceDayStat] = []
            let localKeys = localDays[key] ?? 0
            if localKeys > 0 {
                segments.append(DeviceDayStat(
                    date: key,
                    deviceId: DeviceIdentity.id,
                    deviceName: DeviceIdentity.name,
                    isSelf: true,
                    keystrokes: localKeys
                ))
            }

            let otherSegments = others.compactMap { snap -> DeviceDayStat? in
                guard let day = snap.days[key], day.keystrokes > 0 else { return nil }
                return DeviceDayStat(
                    date: key,
                    deviceId: snap.deviceId,
                    deviceName: snap.deviceName,
                    isSelf: false,
                    keystrokes: day.keystrokes
                )
            }
            .sorted { $0.deviceName < $1.deviceName }

            segments.append(contentsOf: otherSegments)
            return DeviceDayBreakdown(date: key, segments: segments)
        }
    }

    /// Merged per-app totals for today, ranked by keystrokes.
    func topAppsToday(limit: Int = 10) -> [AppStat] {
        let key = StatsService.dateKey(for: Date())
        return mergedApps(onKey: key)
            .map { AppStat(id: nil, date: key, bundleId: $0.key, appName: $0.value.name, keystrokes: $0.value.keys) }
            .sorted { $0.keystrokes > $1.keystrokes }
            .prefix(limit)
            .map { $0 }
    }

    /// Today's top apps grouped per device (this Mac + each synced Mac), so the
    /// UI can show which device the typing happened on. This device comes first
    /// (from the live local DB); other devices follow, busiest first.
    func topAppsTodayByDevice(limit: Int = 10) -> [DeviceAppStats] {
        let key = StatsService.dateKey(for: Date())
        var groups: [DeviceAppStats] = []

        // This device — from the live local DB.
        let localApps = ((try? local.allApps(onKey: key)) ?? [])
            .sorted { $0.keystrokes > $1.keystrokes }
            .prefix(limit)
            .map { $0 }
        if !localApps.isEmpty {
            groups.append(DeviceAppStats(
                id: DeviceIdentity.id, deviceName: DeviceIdentity.name, isSelf: true, apps: localApps))
        }

        // Other devices — from their iCloud snapshots, busiest device first.
        let otherGroups: [DeviceAppStats] = others.compactMap { snap in
            guard let day = snap.days[key], !day.apps.isEmpty else { return nil }
            let apps = day.apps
                .map { AppStat(id: nil, date: key, bundleId: $0.key, appName: $0.value.name, keystrokes: $0.value.keystrokes) }
                .sorted { $0.keystrokes > $1.keystrokes }
                .prefix(limit)
                .map { $0 }
            return DeviceAppStats(id: snap.deviceId, deviceName: snap.deviceName, isSelf: false, apps: apps)
        }
        .sorted { ($0.apps.reduce(0) { $0 + $1.keystrokes }) > ($1.apps.reduce(0) { $0 + $1.keystrokes }) }

        groups.append(contentsOf: otherGroups)
        return groups
    }

    /// Merged per-day totals across all history, oldest→newest (for export).
    func allDays() -> [DailyStat] {
        var totals = [String: Int]()
        for day in (try? local.allDays()) ?? [] { totals[day.date, default: 0] += day.keystrokes }
        for snap in others {
            for (key, day) in snap.days { totals[key, default: 0] += day.keystrokes }
        }
        return totals.keys.sorted().map { DailyStat(date: $0, keystrokes: totals[$0]!) }
    }

    /// Busiest merged app on a given day (for the export's Top-app column).
    func topAppName(onKey key: String) -> String? {
        mergedApps(onKey: key).max { $0.value.keys < $1.value.keys }?.value.name
    }

    /// Every app that has ever recorded input on any device (for the exclude list).
    func knownApps() -> [(bundleId: String, name: String)] {
        var totals = [String: (name: String, keys: Int)]()
        for (bundleId, name) in (try? local.knownApps()) ?? [] {
            totals[bundleId] = (name, totals[bundleId]?.keys ?? 0)
        }
        for snap in others {
            for (_, day) in snap.days {
                for (bundleId, app) in day.apps {
                    var cur = totals[bundleId] ?? (app.name, 0)
                    cur.keys += app.keystrokes
                    cur.name = app.name
                    totals[bundleId] = cur
                }
            }
        }
        return totals.sorted { $0.value.keys > $1.value.keys }.map { ($0.key, $0.value.name) }
    }

    // MARK: - Helpers

    private func mergedApps(onKey key: String) -> [String: (name: String, keys: Int)] {
        var totals = [String: (name: String, keys: Int)]()
        for a in (try? local.allApps(onKey: key)) ?? [] {
            var cur = totals[a.bundleId] ?? (a.appName, 0)
            cur.keys += a.keystrokes
            cur.name = a.appName
            totals[a.bundleId] = cur
        }
        for snap in others {
            guard let day = snap.days[key] else { continue }
            for (bundleId, app) in day.apps {
                var cur = totals[bundleId] ?? (app.name, 0)
                cur.keys += app.keystrokes
                cur.name = app.name
                totals[bundleId] = cur
            }
        }
        return totals
    }

    static func lastDayKeys(_ count: Int) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        return (0..<count).compactMap { i in
            cal.date(byAdding: .day, value: -i, to: today).map(StatsService.dateKey(for:))
        }.reversed()
    }
}
