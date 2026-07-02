import SwiftUI
import Charts

struct HistoryChartView: View {
    @State private var days: [DailyStat] = []
    @State private var range = 30

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

            if days.allSatisfy({ $0.keystrokes == 0 }) {
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
        Chart(days, id: \.date) { day in
            BarMark(
                x: .value("日期", shortLabel(day.date)),
                y: .value("字数", CharEstimate.characters(fromKeystrokes: day.keystrokes, factor: factor))
            )
            .foregroundStyle(Color.accentColor)
        }
    }

    private var totals: some View {
        let totalKeys = days.reduce(0) { $0 + $1.keystrokes }
        let total = CharEstimate.characters(fromKeystrokes: totalKeys, factor: factor)
        let activeDays = days.filter { $0.keystrokes > 0 }.count
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

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(.tertiary)
            Text("这段时间还没有记录").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() {
        // MergedStats.recentDays already returns the last N days oldest→newest,
        // summed across this device and all synced devices.
        days = MergedStats().recentDays(range)
    }

    /// "2026-06-18" → "06-18"
    private func shortLabel(_ key: String) -> String {
        String(key.suffix(5))
    }
}
