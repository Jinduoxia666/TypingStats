import Foundation

/// Builds CSV / JSON exports of the daily stats. Pure (no UI) so it stays
/// testable; the save panel lives in ExportView.
struct StatsExporter {
    struct Row: Encodable {
        let date: String
        let keystrokes: Int
        let characters: Int
        let topApp: String

        enum CodingKeys: String, CodingKey {
            case date
            case keystrokes
            case characters
            case topApp = "top_app"
        }
    }

    func rows() throws -> [Row] {
        let merged = MergedStats()   // snapshots read once, reused for every day
        let factor = CharEstimate.factor
        return merged.allDays().map { day in
            let topApp = merged.topAppName(onKey: day.date) ?? ""
            return Row(
                date: day.date,
                keystrokes: day.keystrokes,
                characters: CharEstimate.characters(fromKeystrokes: day.keystrokes, factor: factor),
                topApp: topApp
            )
        }
    }

    func csv() throws -> String {
        var out = "date,keystrokes,characters,top_app\n"
        for r in try rows() {
            out += [
                r.date,
                String(r.keystrokes),
                String(r.characters),
                escapeCSV(r.topApp),
            ].joined(separator: ",") + "\n"
        }
        return out
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(try rows())
        return String(decoding: data, as: UTF8.self)
    }

    private func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
