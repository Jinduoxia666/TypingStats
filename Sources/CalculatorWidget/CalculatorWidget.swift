import SwiftUI
import WidgetKit

struct CalculatorEntry: TimelineEntry {
    var date: Date
    var theme: CalculatorTheme
    var state: CalculatorModel.Snapshot
}

struct CalculatorProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CalculatorEntry {
        CalculatorEntry(date: .now, theme: .cream, state: CalculatorModel().snapshot)
    }

    func snapshot(for configuration: CalculatorConfiguration, in context: Context) async -> CalculatorEntry {
        CalculatorEntry(date: .now, theme: configuration.theme, state: await CalculatorWidgetStore.shared.snapshot())
    }

    func timeline(for configuration: CalculatorConfiguration, in context: Context) async -> Timeline<CalculatorEntry> {
        Timeline(entries: [await snapshot(for: configuration, in: context)], policy: .never)
    }
}

@main
struct CalculatorWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TypingStatsCalculator", intent: CalculatorConfiguration.self,
                               provider: CalculatorProvider()) { entry in
            CalculatorWidgetView(entry: entry)
                .containerBackground(for: .widget) { Rectangle().fill(entry.theme.shell.gradient) }
        }
        .configurationDisplayName("桌面计算器")
        .description("直接点击按键计算，支持奶油复古、薄荷青瓷和午夜可可三款配色。")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}
