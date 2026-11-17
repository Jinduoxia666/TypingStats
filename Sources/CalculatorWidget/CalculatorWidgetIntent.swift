import AppIntents
import WidgetKit

extension CalculatorTheme: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "配色"
    static var caseDisplayRepresentations: [CalculatorTheme: DisplayRepresentation] = [
        .cream: "奶油复古", .mint: "薄荷青瓷", .cocoa: "午夜可可"
    ]
}

struct CalculatorConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "计算器配色"
    static var description = IntentDescription("选择桌面计算器的外观。")

    @Parameter(title: "配色", default: .cream)
    var theme: CalculatorTheme
}

struct CalculatorKeyIntent: AppIntent {
    static var title: LocalizedStringResource = "计算器按键"
    static var isDiscoverable = false
    static var openAppWhenRun = false

    @Parameter(title: "按键")
    var key: String

    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        try await CalculatorWidgetStore.shared.press(key)
        return .result()
    }
}
