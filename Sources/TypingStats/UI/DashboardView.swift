import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    @State private var todayApps: [DashboardAppBreakdown] = []
    @State private var weekDays: [DeviceDayBreakdown] = []
    /// Keystroke counts at the last reload, so the periodic refresh can skip
    /// passes where nothing changed.
    @State private var lastReloadedCounts: (local: Int, others: Int) = (-1, -1)
    @State private var isReloadingToday = false
    @State private var needsTodayReload = false
    /// Merged stats reads snapshot files off disk; refresh them on a slow tick
    /// instead of per keystroke (the headline number is live via `state`).
    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            todayTab.tabItem { Label("今日", systemImage: "calendar") }
            HistoryChartView().tabItem { Label("历史", systemImage: "chart.bar") }
            TopAppView().tabItem { Label("应用", systemImage: "app.badge") }
            ClipboardHistoryView().tabItem { Label("剪贴板", systemImage: "clipboard") }
        }
        .padding()
    }

    private var todayTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 10) {
                    FlipNumberText(value: totalChars)
                    Text("字")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("今日")
                            .font(.headline)
                        Text(todayDateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 164)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statTile("本机", "\(localChars) 字", "desktopcomputer")
                    statTile("其他设备", "\(otherDevicesChars) 字", "laptopcomputer")
                    statTile("同步设备", "\(deviceCount) 台", "icloud")
                    statTile("今日应用", topAppTitle, "app.badge")
                }

                trendSection
                appSummarySection
            }
            .padding(.trailing, 18)
        }
        .padding()
        .onAppear(perform: reloadToday)
        .onReceive(refreshTimer) { _ in
            guard state.todayKeystrokes != lastReloadedCounts.local
                || state.otherDevicesTodayKeystrokes != lastReloadedCounts.others else { return }
            reloadToday()
        }
    }

    private func statTile(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("近 7 天")
                    .font(.headline)
                Spacer()
                Text("日均 \(weeklyAverageChars) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            deviceLegend
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(weekDays) { day in
                    VStack(spacing: 6) {
                        stackedDayBar(day)
                        Text(shortLabel(day.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 118, alignment: .bottom)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var appSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日应用")
                    .font(.headline)
                Spacer()
                Text("\(todayApps.count) 个应用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if todayApps.isEmpty {
                Text("今天还没有应用记录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(todayApps.prefix(3).enumerated()), id: \.element.bundleId) { index, app in
                    appRow(rank: index + 1, app: app)
                }
                deviceLegend
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func appRow(rank: Int, app: DashboardAppBreakdown) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.appName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text("\(chars(app.totalKeystrokes)) 字")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    stackedAppBar(app, width: geo.size.width)
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 4)
    }

    private func chars(_ keystrokes: Int) -> Int {
        CharEstimate.characters(fromKeystrokes: keystrokes, factor: state.keystrokesPerCharacter)
    }

    private var totalChars: Int {
        CharEstimate.characters(fromKeystrokes: state.todayKeystrokesMerged, factor: state.keystrokesPerCharacter)
    }

    private var otherDevicesChars: Int {
        chars(state.otherDevicesTodayKeystrokes)
    }

    private var localChars: Int {
        chars(state.todayKeystrokes)
    }

    private var deviceCount: Int {
        max(state.syncedDevices.count, 1)
    }

    private var topAppTitle: String {
        guard let app = todayApps.first else { return "暂无" }
        return app.appName
    }

    private var maxTopAppChars: Int {
        max(todayApps.map { chars($0.totalKeystrokes) }.max() ?? 1, 1)
    }

    private var weeklyAverageChars: Int {
        let activeDays = weekDays.filter { $0.totalKeystrokes > 0 }
        guard !activeDays.isEmpty else { return 0 }
        let total = activeDays.reduce(0) { $0 + chars($1.totalKeystrokes) }
        return total / activeDays.count
    }

    private var maxWeekChars: Int {
        max(weekDays.map { chars($0.totalKeystrokes) }.max() ?? 1, 1)
    }

    private var todayDateText: String {
        Self.todayDateFormatter.string(from: Date())
    }

    private static let todayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private func barHeight(for day: DeviceDayBreakdown) -> CGFloat {
        let value = chars(day.totalKeystrokes)
        guard value > 0 else { return 8 }
        return max(12, 86 * CGFloat(value) / CGFloat(maxWeekChars))
    }

    private func stackedDayBar(_ day: DeviceDayBreakdown) -> some View {
        let height = barHeight(for: day)
        return VStack(spacing: 0) {
            if day.totalKeystrokes > 0 {
                ForEach(day.segments) { segment in
                    Rectangle()
                        .fill(DeviceColor.color(for: segment.deviceId, isSelf: segment.isSelf).opacity(0.78))
                        .frame(height: max(3, height * CGFloat(segment.keystrokes) / CGFloat(day.totalKeystrokes)))
                }
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.16))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func stackedAppBar(_ app: DashboardAppBreakdown, width: CGFloat) -> some View {
        let totalChars = chars(app.totalKeystrokes)
        let fullWidth = max(4, width * CGFloat(totalChars) / CGFloat(maxTopAppChars))
        return HStack(spacing: 0) {
            ForEach(app.segments) { segment in
                Rectangle()
                    .fill(DeviceColor.color(for: segment.deviceId, isSelf: segment.isSelf).opacity(0.55))
                    .frame(width: max(3, fullWidth * CGFloat(segment.keystrokes) / CGFloat(app.totalKeystrokes)))
            }
        }
        .frame(width: fullWidth, height: 6, alignment: .leading)
        .clipShape(Capsule())
    }

    private var deviceLegend: some View {
        let segments = legendSegments
        return Group {
            if segments.count > 1 {
                HStack(spacing: 10) {
                    ForEach(segments) { segment in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(DeviceColor.color(for: segment.deviceId, isSelf: segment.isSelf))
                                .frame(width: 7, height: 7)
                            Text(segment.isSelf ? "本机" : segment.deviceName)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var legendSegments: [DeviceLegendItem] {
        var items: [DeviceLegendItem] = []
        var seen = Set<String>()

        for segment in weekDays.flatMap(\.segments) {
            if seen.insert(segment.deviceId).inserted {
                items.append(DeviceLegendItem(
                    deviceId: segment.deviceId,
                    deviceName: segment.deviceName,
                    isSelf: segment.isSelf
                ))
            }
        }
        for segment in todayApps.flatMap(\.segments) {
            if seen.insert(segment.deviceId).inserted {
                items.append(DeviceLegendItem(
                    deviceId: segment.deviceId,
                    deviceName: segment.deviceName,
                    isSelf: segment.isSelf
                ))
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.isSelf != rhs.isSelf { return lhs.isSelf }
            return lhs.deviceName < rhs.deviceName
        }
    }

    private func shortLabel(_ key: String) -> String {
        String(key.suffix(5))
    }

    private func reloadToday() {
        guard !isReloadingToday else {
            needsTodayReload = true
            return
        }
        isReloadingToday = true
        lastReloadedCounts = (state.todayKeystrokes, state.otherDevicesTodayKeystrokes)
        DispatchQueue.global(qos: .userInitiated).async {
            let merged = MergedStats()
            let apps = Self.dashboardAppBreakdowns(from: merged.topAppsTodayByDevice(limit: 10), limit: 5)
            let days = merged.recentDaysByDevice(7)
            DispatchQueue.main.async {
                todayApps = apps
                weekDays = days
                isReloadingToday = false
                if needsTodayReload {
                    needsTodayReload = false
                    reloadToday()
                }
            }
        }
    }

    private static func dashboardAppBreakdowns(from groups: [DeviceAppStats], limit: Int) -> [DashboardAppBreakdown] {
        var apps: [String: (name: String, segments: [DashboardAppSegment])] = [:]

        for group in groups {
            for app in group.apps {
                var current = apps[app.bundleId] ?? (app.appName, [])
                current.name = app.appName
                current.segments.append(DashboardAppSegment(
                    bundleId: app.bundleId,
                    deviceId: group.id,
                    deviceName: group.deviceName,
                    isSelf: group.isSelf,
                    keystrokes: app.keystrokes
                ))
                apps[app.bundleId] = current
            }
        }

        return apps.map { bundleId, value in
            DashboardAppBreakdown(
                bundleId: bundleId,
                appName: value.name,
                segments: value.segments.sorted { lhs, rhs in
                    if lhs.isSelf != rhs.isSelf { return lhs.isSelf }
                    return lhs.deviceName < rhs.deviceName
                }
            )
        }
        .sorted { $0.totalKeystrokes > $1.totalKeystrokes }
        .prefix(limit)
        .map { $0 }
    }
}

private struct DashboardAppBreakdown: Identifiable {
    let bundleId: String
    let appName: String
    let segments: [DashboardAppSegment]

    var id: String { bundleId }
    var totalKeystrokes: Int { segments.reduce(0) { $0 + $1.keystrokes } }
}

private struct DashboardAppSegment: Identifiable {
    let bundleId: String
    let deviceId: String
    let deviceName: String
    let isSelf: Bool
    let keystrokes: Int

    var id: String { "\(bundleId)-\(deviceId)" }
}

private struct DeviceLegendItem: Identifiable {
    let deviceId: String
    let deviceName: String
    let isSelf: Bool

    var id: String { deviceId }
}

private struct FlipNumberText: View {
    let value: Int
    @State private var displayedValue: Int = 0

    private var text: String {
        Self.formatter.string(from: NSNumber(value: displayedValue)) ?? "\(displayedValue)"
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, char in
                FlipCharacterView(char: char)
            }
        }
        .font(.system(size: 92, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .frame(height: 154, alignment: .center)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            displayedValue = value
        }
        .onChange(of: value) { newValue in
            withAnimation(.easeInOut(duration: 0.22)) {
                displayedValue = newValue
            }
        }
    }
}

private struct FlipCharacterView: View {
    let char: Character

    var body: some View {
        ZStack(alignment: .center) {
            Text(String(char))
                .id(char)
                .frame(width: char == "," ? 30 : 56, height: 140)
                .transition(.asymmetric(
                    insertion: .offset(y: -96).combined(with: .opacity),
                    removal: .offset(y: 96).combined(with: .opacity)
                ))
        }
        .frame(width: char == "," ? 30 : 56, height: 140, alignment: .center)
        .clipped()
    }
}
