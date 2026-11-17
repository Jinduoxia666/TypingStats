import SwiftUI

struct CalculatorView: View {
    @ObservedObject var model: CalculatorModel
    @AppStorage("calculatorTheme") private var themeChoice = CalculatorTheme.cream.rawValue
    @AppStorage("calculatorPinned") private var pinned = false
    var close: () -> Void
    var setPinned: (Bool) -> Void
    var resize: (Bool) -> Void
    private var theme: CalculatorTheme { CalculatorTheme(rawValue: themeChoice) ?? .cream }
    private let keys = ["C", "7", "8", "9", "÷", "±", "4", "5", "6", "×",
                        "%", "1", "2", "3", "+", "00", "0", ".", "=", "−"]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button(action: close) { Image(systemName: "xmark") }
                    .help("关闭计算器").accessibilityLabel("关闭计算器")
                Spacer()
                Text("DESK CALC").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                Spacer()
                Menu {
                    Picker("配色", selection: $themeChoice) {
                        ForEach(CalculatorTheme.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                } label: { Image(systemName: "paintpalette") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("切换配色").accessibilityLabel("切换配色")
                Button {
                    pinned.toggle()
                    setPinned(pinned)
                } label: { Image(systemName: pinned ? "pin.fill" : "pin") }
                .help(pinned ? "取消置顶" : "始终置顶").accessibilityLabel(pinned ? "取消置顶" : "始终置顶")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.ink)
            .frame(height: 18)

            HStack {
                Button(model.scientific ? "科学 ▾" : "普通 ▾") { model.press("SCI") }
                    .accessibilityLabel("切换科学模式")
                Spacer()
                if model.scientific {
                    Button(model.degrees ? "DEG · 角度" : "RAD · 弧度") { model.press("DEG") }
                        .accessibilityLabel("切换角度单位")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.ink)

            VStack(alignment: .trailing, spacing: 5) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        Text(model.expression)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(0.7)
                            .accessibilityLabel("计算式").accessibilityValue(model.expression)
                            .textSelection(.enabled)
                        Color.clear.frame(height: 1).id("expressionEnd")
                    }
                    .frame(height: 44)
                    .onChange(of: model.expression) { _ in proxy.scrollTo("expressionEnd", anchor: .bottom) }
                }
                HStack(spacing: 8) {
                    Text(model.display)
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.25)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel("计算结果")
                        .accessibilityValue(model.display)
                    Button { model.press("⌫") } label: {
                        Image(systemName: "delete.left").font(.system(size: 12))
                    }
                    .buttonStyle(.plain).help("退格").accessibilityLabel("退格")
                }
            }
            .foregroundStyle(Color(red: 0.15, green: 0.18, blue: 0.12))
            .padding(.horizontal, 12)
            .frame(height: 108)
            .background(theme.screen.shadow(.inner(color: .black.opacity(0.25), radius: 4, x: 1, y: 3)),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.35), lineWidth: 2))

            Rectangle().fill(theme.ink.opacity(0.12)).frame(height: 1)

            HStack(alignment: .bottom, spacing: 16) {
                if model.scientific {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 9), count: 3), spacing: 7) {
                        ForEach(CalculatorModel.scientificKeys, id: \.self) { key in
                            Button { model.press(key) } label: {
                                Text(key).font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .frame(width: 44, height: 34)
                            }
                            .buttonStyle(CalculatorKeyStyle(color: theme.number, selected: false))
                        }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 9), count: 5), spacing: 10) {
                    ForEach(keys, id: \.self) { key in
                        Button { model.press(key) } label: {
                            Text(key).font(.system(size: 23, weight: .semibold, design: .rounded))
                                .frame(width: 44, height: 40)
                        }
                        .buttonStyle(CalculatorKeyStyle(color: keyColor(key), selected: model.operation == key))
                        .accessibilityLabel(key == "C" ? "清零" : key)
                    }
                }
            }

        }
        .padding(18)
        .frame(width: model.scientific ? 466 : 292, height: 420)
        .background(theme.shell.gradient, in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.45), lineWidth: 2))
        .onChange(of: model.scientific) { value in
            UserDefaults.standard.set(value, forKey: "calculatorScientific")
            resize(value)
        }
        .onChange(of: model.degrees) { UserDefaults.standard.set(!$0, forKey: "calculatorRadians") }
        .preferredColorScheme(theme == .cocoa ? .dark : .light)
    }

    private func keyColor(_ key: String) -> Color {
        if ["C", "±", "%", "00"].contains(key) { return theme.accent }
        if ["÷", "×", "+", "−", "="].contains(key) { return theme.dark }
        return theme.number
    }
}

private struct CalculatorKeyStyle: ButtonStyle {
    let color: Color
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(0.95))
            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            .background(color.gradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.85 : 0.3), lineWidth: selected ? 2 : 1))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.1 : 0.3), radius: 1.5,
                    x: 0, y: configuration.isPressed ? 0 : 2)
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}
