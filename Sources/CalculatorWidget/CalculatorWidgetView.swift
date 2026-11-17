import SwiftUI
import WidgetKit

struct CalculatorWidgetView: View {
    let entry: CalculatorEntry
    @Environment(\.widgetFamily) private var family
    private let keys = ["C", "7", "8", "9", "÷", "±", "4", "5", "6", "×",
                        "%", "1", "2", "3", "+", "00", "0", ".", "=", "−"]

    var body: some View {
        GeometryReader { geometry in
            let scientific = entry.state.scientific == true
            let expanded = scientific && family == .systemLarge
            let visibleKeys = scientific ? (expanded ? CalculatorModel.scientificKeys + keys : CalculatorModel.scientificKeys) : keys
            let unit = min(geometry.size.width / 170, geometry.size.height / (expanded ? 280 : 194))
            VStack(spacing: 6 * unit) {
                HStack {
                    Button(intent: CalculatorKeyIntent(key: "SCI")) {
                        Text(scientific ? "科学 · 切换普通" : "普通 · 切换科学")
                    }
                    .accessibilityLabel("切换科学模式")
                    Spacer()
                    if scientific {
                        Button(intent: CalculatorKeyIntent(key: "DEG")) {
                            Text(entry.state.degrees == false ? "RAD" : "DEG")
                        }
                        .accessibilityLabel("切换角度单位")
                    }
                }
                .font(.system(size: 8 * unit, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(entry.theme.ink)
                VStack(alignment: .trailing, spacing: unit) {
                    Text(entry.state.expression)
                        .font(.system(size: 8 * unit, weight: .medium, design: .monospaced))
                        .lineLimit(2).minimumScaleFactor(0.5)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .opacity(0.7)
                        .accessibilityLabel("计算式").accessibilityValue(entry.state.expression)
                        .invalidatableContent()
                    HStack(spacing: 4 * unit) {
                        Text(entry.state.display)
                            .font(.system(size: 22 * unit, weight: .semibold, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.2)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityLabel("计算结果").accessibilityValue(entry.state.display)
                            .invalidatableContent()
                        Button(intent: CalculatorKeyIntent(key: "⌫")) {
                            Image(systemName: "delete.left").font(.system(size: 10 * unit))
                                .frame(width: 16 * unit, height: 28 * unit)
                        }
                        .buttonStyle(.plain).accessibilityLabel("退格")
                    }
                }
                .foregroundStyle(Color(red: 0.15, green: 0.18, blue: 0.12))
                .padding(.horizontal, 6 * unit)
                .frame(height: 54 * unit)
                .background(entry.theme.screen.shadow(.inner(color: .black.opacity(0.25), radius: 2 * unit, y: 2)),
                            in: RoundedRectangle(cornerRadius: 7 * unit))

                Grid(horizontalSpacing: 5 * unit, verticalSpacing: 3 * unit) {
                    ForEach(0..<(visibleKeys.count / 5), id: \.self) { row in
                        GridRow {
                            ForEach(0..<5) { column in
                                let key = visibleKeys[row * 5 + column]
                                Button(intent: CalculatorKeyIntent(key: key)) {
                                    Text(key)
                                        .font(.system(size: 15 * unit, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 22 * unit)
                                        .background(keyColor(key).gradient, in: Capsule())
                                        .overlay(Capsule().strokeBorder(.white.opacity(entry.state.operation == key ? 0.85 : 0.3)))
                                        .shadow(color: .black.opacity(0.25), radius: unit, y: unit)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(key == "C" ? "清零" : key)
                            }
                        }
                    }
                }
            }
            .padding(10 * unit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func keyColor(_ key: String) -> Color {
        if ["C", "±", "%", "00"].contains(key) { return entry.theme.accent }
        if ["÷", "×", "+", "−", "="].contains(key) { return entry.theme.dark }
        return entry.theme.number
    }
}
