import SwiftUI
import Charts
import Combine

/// Keeps live headline updates isolated from navigation and inactive pages.
struct TodayDashboardView: View {
    var isActive: Bool = true

    private enum Period: Int, CaseIterable {
        case today = 1, week = 7, month = 30

        var title: String {
            switch self {
            case .today: return "今日"
            case .week: return "近7天"
            case .month: return "近30天"
            }
        }
    }

    @EnvironmentObject private var model: DashboardStatsModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var todayHours: [DeviceHourBreakdown] = []
    @State private var recentDays: [DeviceDayBreakdown] = []
    @State private var period: Period = .today
    @State private var hoveredIndex: Int?
    @State private var lastReloadedCounts: (local: Int, others: Int) = (-1, -1)
    @State private var lastReloadedDate = ""
    @State private var isReloadingToday = false
    @State private var needsTodayReload = false
    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        if isActive {
            GeometryReader { geometry in
                let compact = geometry.size.height < 430
                VStack(alignment: .leading, spacing: compact ? 12 : 16) {
                    header(compact: compact)
                    HStack(spacing: 10) {
                        statTile("本机", value: chars(stats.todayKeystrokes), unit: "字",
                                 icon: "desktopcomputer", compact: compact, highlighted: true,
                                 comparison: comparison(isSelf: true))
                        statTile("其他设备", value: chars(stats.otherDevicesTodayKeystrokes), unit: "字",
                                 icon: "laptopcomputer", compact: compact,
                                 comparison: comparison(isSelf: false))
                        statTile("同步设备", value: stats.deviceCount, unit: "台",
                                 icon: "icloud", compact: compact)
                    }
                    trendSection(compact: compact)
                }
                .padding(compact ? 16 : 22)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
            .onAppear(perform: reloadToday)
            .onReceive(refreshTimer) { _ in
                guard stats.todayKeystrokes != lastReloadedCounts.local
                    || stats.otherDevicesTodayKeystrokes != lastReloadedCounts.others
                    || lastReloadedDate != StatsService.dateKey(for: Date()) else { return }
                reloadToday()
            }
            .onChange(of: period) { _ in hoveredIndex = nil }
        } else {
            Color.clear
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("今天的输入")
                    .font(.system(size: compact ? 15 : 17, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(chars(stats.todayKeystrokesMerged), format: .number)
                        .font(.system(size: compact ? 48 : 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient(
                            colors: [.blue, colorScheme == .dark ? .white : Color(red: 0.04, green: 0.09, blue: 0.22)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("字").font(.title3).foregroundStyle(.secondary)
                }
                Text("保持专注，持续输入，就是进步 💪")
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Label(Self.dateFormatter.string(from: Date()), systemImage: "calendar")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.primary.opacity(0.025), in: Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(0.08)) }
                .padding(.top, 8)
        }
    }

    private func statTile(_ title: String, value: Int, unit: String, icon: String,
                          compact: Bool, highlighted: Bool = false,
                          comparison: (text: String, color: Color)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: compact ? 21 : 25, weight: .regular))
                .foregroundStyle(highlighted || icon == "icloud" ? Color.blue : Color.secondary)
                .frame(width: compact ? 38 : 48, height: compact ? 42 : 48)
                .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(highlighted ? Color.blue : Color.secondary)
                Text("\(value.formatted()) \(unit)")
                    .font(.system(size: compact ? 19 : 23, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if let comparison {
                    Text(comparison.text).foregroundStyle(comparison.color)
                    Text("较昨日").foregroundStyle(.secondary)
                } else {
                    Text("包含本机").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: compact ? 10 : 11, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(compact ? 11 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Color.blue.opacity(0.055) : cardColor,
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(highlighted ? Color.blue.opacity(0.2) : Color.white.opacity(colorScheme == .dark ? 0.1 : 0.85))
        }
    }

    private func trendSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack {
                Text(period == .today ? "今日输入趋势" : "\(period.title)输入趋势")
                    .font(.system(size: compact ? 15 : 17, weight: .semibold))
                Spacer()
                Picker("时间范围", selection: $period) {
                    ForEach(Period.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: compact ? 194 : 214)
            }
            deviceLegend
            trendChart
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.1 : 0.9))
        }
    }

    private var trendChart: some View {
        let points = chartPoints
        return Chart {
            ForEach(points) { point in
                AreaMark(x: .value("时间", point.index), y: .value("字数", point.chars),
                         series: .value("设备", point.deviceId), stacking: .unstacked)
                    .foregroundStyle(LinearGradient(colors: [point.color.opacity(0.28), point.color.opacity(0.015)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("时间", point.index), y: .value("字数", point.chars),
                         series: .value("设备", point.deviceId))
                    .foregroundStyle(point.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let hoveredIndex {
                RuleMark(x: .value("时间", hoveredIndex))
                    .foregroundStyle(.blue.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ForEach(points.filter { $0.index == hoveredIndex }) { point in
                    PointMark(x: .value("时间", point.index), y: .value("字数", point.chars))
                        .foregroundStyle(point.color)
                        .symbolSize(45)
                }
            }
        }
        .chartXScale(domain: 0...(period == .today ? 23 : period.rawValue - 1))
        .chartYScale(domain: 0...max(Int(Double(points.map(\.chars).max() ?? 0) * 1.1), 10))
        .chartXAxis {
            AxisMarks(values: axisIndices) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel {
                    if let index = value.as(Int.self) { Text(axisLabel(index)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.25))
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let plot = geometry[proxy.plotAreaFrame]
                            guard plot.contains(location) else { hoveredIndex = nil; return }
                            hoveredIndex = proxy.value(atX: location.x - plot.minX, as: Double.self)
                                .map { min(max(Int($0.rounded()), 0), period == .today ? 23 : period.rawValue - 1) }
                        case .ended: hoveredIndex = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let hoveredIndex {
                VStack(alignment: .leading, spacing: 6) {
                    Text(axisLabel(hoveredIndex)).foregroundStyle(.secondary)
                    ForEach(points.filter { $0.index == hoveredIndex }) { point in
                        HStack(spacing: 6) {
                            Circle().fill(point.color).frame(width: 6, height: 6)
                            Text(point.deviceName).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(point.chars.formatted()) 字").monospacedDigit()
                        }
                    }
                }
                .font(.caption)
                .padding(10)
                .frame(width: 185)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                .padding(6)
            }
        }
        .frame(minHeight: 60, maxHeight: .infinity)
    }

    private var deviceLegend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                ForEach(devices) { device in
                    HStack(spacing: 5) {
                        Circle().fill(device.color).frame(width: 8, height: 8)
                        Text(device.name).lineLimit(1)
                    }
                }
            }
            Text("\(devices.count) 台设备 · 悬停查看明细")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var cardColor: Color { colorScheme == .dark ? .white.opacity(0.045) : .white.opacity(0.62) }
    private var stats: DashboardStatsSnapshot { model.snapshot }
    private var selectedDays: [DeviceDayBreakdown] { Array(recentDays.suffix(period.rawValue)) }

    private func chars(_ keystrokes: Int) -> Int {
        CharEstimate.characters(fromKeystrokes: keystrokes, factor: stats.keystrokesPerCharacter)
    }

    private func comparison(isSelf: Bool) -> (text: String, color: Color) {
        guard recentDays.count >= 2 else { return ("—", .secondary) }
        let yesterday = recentDays[recentDays.count - 2].segments
            .filter { $0.isSelf == isSelf }.reduce(0) { $0 + $1.keystrokes }
        let current = isSelf ? stats.todayKeystrokes : stats.otherDevicesTodayKeystrokes
        guard yesterday > 0 else { return (current > 0 ? "新增" : "—", .secondary) }
        let percent = (Double(current) / Double(yesterday) - 1) * 100
        if abs(percent) < 0.5 { return ("持平", .secondary) }
        return (String(format: "%@ %.0f%%", percent > 0 ? "↑" : "↓", abs(percent)), percent > 0 ? .green : .red)
    }

    private var devices: [ChartDevice] {
        var result = [DeviceIdentity.id: ChartDevice(id: DeviceIdentity.id, name: "本机", isSelf: true)]
        if period == .today {
            for segment in todayHours.flatMap(\.segments) {
                result[segment.deviceId] = ChartDevice(id: segment.deviceId, name: segment.isSelf ? "本机" : segment.deviceName, isSelf: segment.isSelf)
            }
        } else {
            for segment in selectedDays.flatMap(\.segments) {
                result[segment.deviceId] = ChartDevice(id: segment.deviceId, name: segment.isSelf ? "本机" : segment.deviceName, isSelf: segment.isSelf)
            }
        }
        return result.values.sorted { $0.isSelf != $1.isSelf ? $0.isSelf : $0.name < $1.name }
    }

    private var chartPoints: [TrendPoint] {
        devices.flatMap { device in
            if period == .today {
                return todayHours.map { hour in
                    TrendPoint(index: hour.hour, device: device,
                               chars: chars(hour.segments.first { $0.deviceId == device.id }?.keystrokes ?? 0))
                }
            }
            return selectedDays.enumerated().map { index, day in
                TrendPoint(index: index, device: device,
                           chars: chars(day.segments.first { $0.deviceId == device.id }?.keystrokes ?? 0))
            }
        }
    }

    private var axisIndices: [Int] {
        switch period {
        case .today: return Array(stride(from: 0, through: 21, by: 3))
        case .week: return Array(0..<7)
        case .month: return [0, 5, 10, 15, 20, 25, 29]
        }
    }

    private func axisLabel(_ index: Int) -> String {
        if period == .today { return String(format: "%02d:00", index) }
        let days = selectedDays
        guard days.indices.contains(index) else { return "" }
        return String(days[index].date.suffix(5)).replacingOccurrences(of: "-", with: "/")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private func reloadToday() {
        guard !isReloadingToday else { needsTodayReload = true; return }
        isReloadingToday = true
        lastReloadedCounts = (stats.todayKeystrokes, stats.otherDevicesTodayKeystrokes)
        lastReloadedDate = StatsService.dateKey(for: Date())
        DispatchQueue.global(qos: .userInitiated).async {
            let merged = MergedStats()
            let hours = merged.todayHoursByDevice()
            let days = merged.recentDaysByDevice(30)
            DispatchQueue.main.async {
                todayHours = hours
                recentDays = days
                isReloadingToday = false
                if needsTodayReload { needsTodayReload = false; reloadToday() }
            }
        }
    }
}

private struct ChartDevice: Identifiable {
    let id: String
    let name: String
    let isSelf: Bool
    var color: Color { DeviceColor.color(for: id, isSelf: isSelf) }
}

private struct TrendPoint: Identifiable {
    let index: Int
    let device: ChartDevice
    let chars: Int
    var id: String { "\(index)-\(device.id)" }
    var deviceId: String { device.id }
    var deviceName: String { device.name }
    var color: Color { device.color }
}
