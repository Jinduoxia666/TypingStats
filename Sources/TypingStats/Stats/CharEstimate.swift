import Foundation

/// Converts counted keystrokes (the 26 letters + digits 0–9) into an estimated
/// character count.
///
/// A keystroke tap can't tell Chinese pinyin input from direct English typing,
/// so we divide all counted keystrokes by a single "average keystrokes per
/// character" factor. For Chinese pinyin this is ~2–3; set it to 1 for pure
/// English. Configurable; defaults to 2.0.
enum CharEstimate {
    static let defaultFactor = 2.0
    static let factorKey = "keystrokesPerCharacter"

    /// The user-configured factor, read from UserDefaults (falls back to default).
    static var factor: Double {
        let v = UserDefaults.standard.double(forKey: factorKey)
        return v > 0 ? v : defaultFactor
    }

    /// Estimated characters for a keystroke count under the given factor.
    static func characters(fromKeystrokes keystrokes: Int, factor: Double) -> Int {
        guard factor > 0 else { return keystrokes }
        return Int((Double(keystrokes) / factor).rounded())
    }
}
