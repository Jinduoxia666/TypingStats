import SwiftUI
import Charts

struct DashboardView: View {
    var body: some View {
        TabView {
            TodayDashboardView().tabItem { Label("今日", systemImage: "calendar") }
            HistoryChartView().tabItem { Label("历史", systemImage: "chart.bar") }
            TopAppView().tabItem { Label("应用", systemImage: "app.badge") }
            ClipboardHistoryView().tabItem { Label("剪贴板", systemImage: "clipboard") }
            NetworkSpeedTestView().tabItem { Label("测速", systemImage: "speedometer") }
        }
        .padding()
    }
}

/// Keeps the frequently changing statistics below the stable TabView shell.
/// AppState publishes hardware, sync, clipboard, and typing updates; observing it
/// in DashboardView would rebuild the tab labels for every unrelated change.
private struct TodayDashboardView: View {
    @EnvironmentObject private var model: DashboardStatsModel
    @State private var todayApps: [DashboardAppBreakdown] = []
    @State private var todayHours: [DeviceHourBreakdown] = []
    @State private var hoveredHour: Int?
    /// Keystroke counts at the last reload, so the periodic refresh can skip
    /// passes where nothing changed.
    @State private var lastReloadedCounts: (local: Int, others: Int) = (-1, -1)
    @State private var isReloadingToday = false
    @State private var needsTodayReload = false
    /// Merged stats reads snapshot files off disk; refresh them on a slow tick
    /// instead of per keystroke (the headline number is live via `model`).
    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
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
            guard stats.todayKeystrokes != lastReloadedCounts.local
                || stats.otherDevicesTodayKeystrokes != lastReloadedCounts.others else { return }
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
                Text("今日趋势")
                    .font(.headline)
                Spacer()
                // Doubles as the hover readout, so the chart itself needs no
                // floating tooltip that could clip at the card's edges.
                Text(hoveredHourText ?? peakHourText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            deviceLegend
            hourChart
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var hourChart: some View {
        Chart {
            ForEach(hourSeries) { point in
                AreaMark(
                    x: .value("时间", point.hour),
                    y: .value("字数", point.chars),
                    series: .value("设备", point.deviceId),
                    stacking: .standard
                )
                .foregroundStyle(areaGradient(for: point))
                .interpolationMethod(.monotone)
            }

            // Rides exactly on top of the stacked areas (their sum), so it reads
            // as the day's total curve however many devices are involved.
            ForEach(todayHours) { hour in
                LineMark(
                    x: .value("时间", hour.hour),
                    y: .value("字数", chars(hour.totalKeystrokes))
                )
                .foregroundStyle(totalLineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .interpolationMethod(.monotone)
            }

            RuleMark(x: .value("时间", currentHour))
                .foregroundStyle(.secondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

            if let hoveredHour {
                RuleMark(x: .value("时间", hoveredHour))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Int.self) { Text("\(hour)") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let x = location.x - geo[proxy.plotAreaFrame].origin.x
                            hoveredHour = proxy.value(atX: x, as: Int.self)
                                .map { min(max($0, 0), 23) }
                        case .ended:
                            hoveredHour = nil
                        }
                    }
            }
        }
        .frame(height: 132)
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
        CharEstimate.characters(fromKeystrokes: keystrokes, factor: stats.keystrokesPerCharacter)
    }

    private var totalChars: Int {
        CharEstimate.characters(fromKeystrokes: stats.todayKeystrokesMerged, factor: stats.keystrokesPerCharacter)
    }

    private var otherDevicesChars: Int {
        chars(stats.otherDevicesTodayKeystrokes)
    }

    private var localChars: Int {
        chars(stats.todayKeystrokes)
    }

    private var deviceCount: Int {
        stats.deviceCount
    }

    private var stats: DashboardStatsSnapshot { model.snapshot }

    private var topAppTitle: String {
        guard let app = todayApps.first else { return "暂无" }
        return app.appName
    }

    private var maxTopAppChars: Int {
        max(todayApps.map { chars($0.totalKeystrokes) }.max() ?? 1, 1)
    }

    /// Busiest hour so far today, e.g. "峰值 14 时 · 1203 字".
    private var peakHourText: String {
        guard let peak = todayHours.max(by: { $0.totalKeystrokes < $1.totalKeystrokes }),
              peak.totalKeystrokes > 0 else {
            return "今天还没有记录"
        }
        return "峰值 \(peak.hour) 时 · \(chars(peak.totalKeystrokes)) 字"
    }

    private var currentHour: Int {
        StatsService.hourKey(for: Date())
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

    /// One point per (device, hour). Hours a device didn't type in still get a
    /// zero: an area series has to be continuous, otherwise Charts draws a
    /// straight line across the gap instead of dropping to the baseline.
    private var hourSeries: [HourPoint] {
        let devices = hourChartDevices
        guard !devices.isEmpty else { return [] }
        return todayHours.flatMap { hour in
            devices.map { device in
                let keystrokes = hour.segments.first { $0.deviceId == device.deviceId }?.keystrokes ?? 0
                return HourPoint(
                    hour: hour.hour,
                    deviceId: device.deviceId,
                    isSelf: device.isSelf,
                    chars: chars(keystrokes)
                )
            }
        }
    }

    /// Devices that typed at all today, this Mac first — the stacking order.
    private var hourChartDevices: [DeviceLegendItem] {
        Self.devices(
            in: todayHours.flatMap(\.segments).map {
                ($0.deviceId, $0.deviceName, $0.isSelf)
            }
        )
    }

    private func areaGradient(for point: HourPoint) -> LinearGradient {
        let color = DeviceColor.color(for: point.deviceId, isSelf: point.isSelf)
        return LinearGradient(
            colors: [color.opacity(0.45), color.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// With a single device the total *is* that device's line, so it keeps its
    /// colour; once several devices stack, a neutral line reads as the sum
    /// rather than as one more device.
    private var totalLineColor: Color {
        let devices = hourChartDevices
        guard devices.count == 1, let only = devices.first else { return .primary.opacity(0.55) }
        return DeviceColor.color(for: only.deviceId, isSelf: only.isSelf)
    }

    private var hoveredHourText: String? {
        guard let hoveredHour,
              let breakdown = todayHours.first(where: { $0.hour == hoveredHour }) else { return nil }
        return "\(hoveredHour) 时 · \(chars(breakdown.totalKeystrokes)) 字"
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
        Self.devices(
            in: todayHours.flatMap(\.segments).map {
                ($0.deviceId, $0.deviceName, $0.isSelf)
            }
            + todayApps.flatMap(\.segments).map {
                ($0.deviceId, $0.deviceName, $0.isSelf)
            }
        )
    }

    /// Dedupes devices by id and orders them this-Mac-first, then by name — the
    /// order both the legend and the chart's stacking follow.
    private static func devices(
        in segments: [(deviceId: String, deviceName: String, isSelf: Bool)]
    ) -> [DeviceLegendItem] {
        var items: [DeviceLegendItem] = []
        var seen = Set<String>()
        for device in segments where seen.insert(device.deviceId).inserted {
            items.append(DeviceLegendItem(
                deviceId: device.deviceId,
                deviceName: device.deviceName,
                isSelf: device.isSelf
            ))
        }
        return items.sorted { lhs, rhs in
            if lhs.isSelf != rhs.isSelf { return lhs.isSelf }
            return lhs.deviceName < rhs.deviceName
        }
    }

    private func reloadToday() {
        guard !isReloadingToday else {
            needsTodayReload = true
            return
        }
        isReloadingToday = true
        lastReloadedCounts = (stats.todayKeystrokes, stats.otherDevicesTodayKeystrokes)
        DispatchQueue.global(qos: .userInitiated).async {
            let merged = MergedStats()
            let apps = Self.dashboardAppBreakdowns(from: merged.topAppsTodayByDevice(limit: 10), limit: 5)
            let hours = merged.todayHoursByDevice()
            DispatchQueue.main.async {
                todayApps = apps
                todayHours = hours
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

/// One device's contribution in one hour, flattened for the area chart.
private struct HourPoint: Identifiable {
    let hour: Int
    let deviceId: String
    let isSelf: Bool
    let chars: Int

    var id: String { "\(hour)-\(deviceId)" }
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
