import Foundation
import GRDB

struct DailyStat: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "daily_stat"

    var date: String          // YYYY-MM-DD in local tz
    var keystrokes: Int = 0

    enum CodingKeys: String, CodingKey {
        case date
        case keystrokes
    }
}

struct AppStat: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "app_stat"

    var id: Int64?
    var date: String
    var bundleId: String
    var appName: String
    var keystrokes: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case bundleId = "bundle_id"
        case appName = "app_name"
        case keystrokes
    }
}
