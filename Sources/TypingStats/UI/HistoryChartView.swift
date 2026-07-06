import SwiftUI
import Charts

struct HistoryChartView: View {
    @State private var days: [DeviceDayBreakdown] = []
    @State private var range = 7
    @State private var selectedDate: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("历史趋势").font(.headline)
                Spacer()
                Picker("", selection: $range) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if days.allSatisfy({ $0.totalKeystrokes == 0 }) {
                emptyState
            } else {
                chart
                totals
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: reload)
        .onChange(of: range) { _ in reload() }
    }

    private var factor: Double { CharEstimate.factor }

    private var chart: some View {
        ZStack(alignment: .topTrailing) {
            Chart(chartSegments) { segment in
                BarMark(
                    x: .value("日期", segment.date),
                    y: .value("字数", chars(segment.keystrokes))
                )
                .foregroundStyle(segmentColor(segment))
            }
            .chartXAxis {
                AxisMarks(values: days.map(\.date)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let key = value.as(String.self) {
                            Text(shortLabel(key))
                        }
                    }
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
                                let frame = geo[proxy.plotAreaFrame]
                                let x = location.x - frame.origin.x
                                selectedDate = proxy.value(atX: x, as: String.self)
                            case .ended:
                                selectedDate = nil
                            }
                        }
                }
            }

            if let selectedDay {
                tooltip(for: selectedDay)
            }
        }
        .frame(minHeight: 260)
    }

    private var totals: some View {
        let totalKeys = days.reduce(0) { $0 + $1.totalKeystrokes }
        let total = CharEstimate.characters(fromKeystrokes: totalKeys, factor: factor)
        let activeDays = days.filter { $0.totalKeystrokes > 0 }.count
        let average = activeDays > 0 ? total / activeDays : 0
        return HStack(spacing: 24) {
            totalItem("字数合计", total)
            totalItem("日均字数(有记录的天)", average)
        }
        .font(.callout)
    }

    private func totalItem(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary).font(.caption)
            Text("\(value)").monospacedDigit().fontWeight(.medium)
        }
    }

    private var chartSegments: [DeviceDayStat] {
        days.flatMap(\.segments)
    }

    private var selectedDay: DeviceDayBreakdown? {
        guard let selectedDate else { return nil }
        return days.first { $0.date == selectedDate && $0.totalKeystrokes > 0 }
    }

    private func chars(_ keystrokes: Int) -> Int {
        CharEstimate.characters(fromKeystrokes: keystrokes, factor: factor)
    }

    private func segmentColor(_ segment: DeviceDayStat) -> Color {
        if segment.isSelf { return .accentColor }
        let palette: [Color] = [.orange, .green, .purple, .pink, .teal]
        let value = abs(segment.deviceId.hashValue)
        return palette[value % palette.count]
    }

    private func tooltip(for day: DeviceDayBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shortLabel(day.date))
                .font(.caption)
                .fontWeight(.semibold)
            ForEach(day.segments) { segment in
                HStack(spacing: 6) {
                    Circle()
                        .fill(segmentColor(segment))
                        .frame(width: 7, height: 7)
                    Text(segment.isSelf ? "本机" : segment.deviceName)
                    Spacer()
                    Text("\(chars(segment.keystrokes)) 字")
                        .monospacedDigit()
                }
            }
            Divider()
            HStack {
                Text("合计")
                Spacer()
                Text("\(chars(day.totalKeystrokes)) 字")
                    .monospacedDigit()
            }
            .fontWeight(.medium)
        }
        .font(.caption)
        .padding(10)
        .frame(width: 180)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 6, y: 2)
        .padding(8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(.tertiary)
            Text("这段时间还没有记录").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() {
        days = MergedStats().recentDaysByDevice(range)
        selectedDate = nil
    }

    /// "2026-06-18" → "06-18"
    private func shortLabel(_ key: String) -> String {
        String(key.suffix(5))
    }
}
