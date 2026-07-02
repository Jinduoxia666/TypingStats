import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            todayTab.tabItem { Label("今日", systemImage: "calendar") }
            HistoryChartView().tabItem { Label("历史", systemImage: "chart.bar") }
            TopAppView().tabItem { Label("应用", systemImage: "app.badge") }
        }
        .padding()
    }

    private var todayTab: some View {
        VStack(spacing: 24) {
            bigNumber(
                CharEstimate.characters(fromKeystrokes: state.todayKeystrokesMerged, factor: state.keystrokesPerCharacter),
                label: "今日字数(估算)"
            )
            Text("\(state.todayKeystrokesMerged) 次字母/数字按键 ÷ 每字 \(String(format: "%.1f", state.keystrokesPerCharacter)) 键")
                .font(.callout)
                .foregroundStyle(.secondary)
            if state.otherDevicesTodayKeystrokes > 0 {
                Text("其中其它设备贡献 \(state.otherDevicesTodayKeystrokes) 次")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
    }

    private func bigNumber(_ value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label).foregroundStyle(.secondary)
        }
    }
}
