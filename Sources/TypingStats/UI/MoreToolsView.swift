import SwiftUI

struct MoreToolsView: View {
    let isActive: Bool

    enum Tool: String, CaseIterable, Identifiable {
        case history = "历史趋势"
        case apps = "应用统计"
        case network = "网络测速"

        var id: Self { self }

        var shortcut: KeyEquivalent {
            switch self {
            case .history: return "4"
            case .apps: return "5"
            case .network: return "6"
            }
        }

        var symbol: String {
            switch self {
            case .history: return "chart.xyaxis.line"
            case .apps: return "square.grid.2x2"
            case .network: return "speedometer"
            }
        }
    }

    let selection: Tool
    @State private var loadedTools: Set<Tool> = []

    var body: some View {
        // Keep the model-owning roots mounted when this entire tab hides.
        ZStack {
            tool(.history) { HistoryChartView(isActive: isActive && selection == .history) }
            tool(.apps) { TopAppView(isActive: isActive && selection == .apps) }
            tool(.network) { NetworkSpeedTestView(isActive: isActive && selection == .network) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadedTools.insert(selection) }
        .onChange(of: selection) { loadedTools.insert($0) }
    }

    @ViewBuilder
    private func tool<Content: View>(_ tool: Tool, @ViewBuilder content: () -> Content) -> some View {
        if selection == tool || loadedTools.contains(tool) {
            content()
                .allowsHitTesting(isActive && selection == tool)
                .accessibilityHidden(!isActive || selection != tool)
        }
    }
}
