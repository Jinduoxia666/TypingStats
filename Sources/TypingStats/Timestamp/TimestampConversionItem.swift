import Foundation

struct TimestampConversionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let value: String

    static func items(input: String, now: Date = Date()) -> [TimestampConversionItem] {
        var result: [TimestampConversionItem] = []
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            if let date = parseTimestamp(trimmed) {
                result.append(
                    TimestampConversionItem(
                        id: "timestamp-to-string",
                        title: "转为标准时间",
                        subtitle: trimmed,
                        value: standardFormatter.string(from: date)
                    )
                )
            }

            if let date = parseDate(trimmed) {
                result.append(
                    TimestampConversionItem(
                        id: "string-to-timestamp",
                        title: "转为时间戳",
                        subtitle: standardFormatter.string(from: date),
                        value: String(Int(date.timeIntervalSince1970))
                    )
                )
                result.append(
                    TimestampConversionItem(
                        id: "string-to-milliseconds",
                        title: "转为毫秒时间戳",
                        subtitle: standardFormatter.string(from: date),
                        value: String(Int(date.timeIntervalSince1970 * 1000))
                    )
                )
            }
        }

        result.append(
            TimestampConversionItem(
                id: "now-timestamp",
                title: "当前时间戳",
                subtitle: "秒",
                value: String(Int(now.timeIntervalSince1970))
            )
        )
        result.append(
            TimestampConversionItem(
                id: "now-milliseconds",
                title: "当前毫秒时间戳",
                subtitle: "毫秒",
                value: String(Int(now.timeIntervalSince1970 * 1000))
            )
        )
        result.append(
            TimestampConversionItem(
                id: "now-string",
                title: "当前标准时间",
                subtitle: "yyyy-MM-dd HH:mm:ss",
                value: standardFormatter.string(from: now)
            )
        )

        return result
    }

    static func isConvertibleInput(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return parseTimestamp(trimmed) != nil || parseDate(trimmed) != nil
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        guard let number = Double(value) else { return nil }
        let seconds = abs(number) >= 10_000_000_000 ? number / 1000 : number
        return Date(timeIntervalSince1970: seconds)
    }

    private static func parseDate(_ value: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return isoFormatter.date(from: value)
    }

    private static let standardFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let dateFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy/MM/dd HH:mm",
        "yyyy-MM-dd",
        "yyyy/MM/dd"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    private static let isoFormatter = ISO8601DateFormatter()
}
