import SwiftUI

enum DeviceColor {
    private static let palette: [Color] = [.orange, .green, .purple, .pink, .teal, .indigo]

    static func color(for deviceId: String, isSelf: Bool) -> Color {
        if isSelf { return .accentColor }

        let value = deviceId.unicodeScalars.reduce(UInt64(5381)) { hash, scalar in
            ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return palette[Int(value % UInt64(palette.count))]
    }
}
