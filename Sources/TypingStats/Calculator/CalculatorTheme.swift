import SwiftUI

enum CalculatorTheme: String, CaseIterable, Identifiable {
    case cream, mint, cocoa
    var id: String { rawValue }
    var name: String {
        switch self {
        case .cream: return "奶油复古"
        case .mint: return "薄荷青瓷"
        case .cocoa: return "午夜可可"
        }
    }
    var shell: Color { color(0xF4E8BC, 0xD8EBE1, 0x403935) }
    var number: Color { color(0xE8D9A5, 0xB8D9CB, 0x716158) }
    var accent: Color { color(0xB72912, 0x357A70, 0xD79972) }
    var dark: Color { color(0x292516, 0x234C48, 0x211F20) }
    var screen: Color { color(0xB8BE9C, 0xA9C6BC, 0xBFC3A2) }
    var ink: Color { color(0x514B32, 0x30574E, 0xF1DFC9) }

    private func color(_ cream: UInt32, _ mint: UInt32, _ cocoa: UInt32) -> Color {
        let hex = self == .cream ? cream : (self == .mint ? mint : cocoa)
        return Color(red: Double((hex >> 16) & 255) / 255,
                     green: Double((hex >> 8) & 255) / 255,
                     blue: Double(hex & 255) / 255)
    }
}
