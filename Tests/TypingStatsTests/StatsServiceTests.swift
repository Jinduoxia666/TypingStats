import XCTest
@testable import TypingStats

final class StatsServiceTests: XCTestCase {
    func testDateKeyFormat() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 2
        comps.hour = 15
        comps.timeZone = .current
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(StatsService.dateKey(for: date), "2026-07-02")
    }

    func testHourKeyUsesLocalHour() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 2
        comps.hour = 15
        comps.minute = 59
        comps.timeZone = .current
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(StatsService.hourKey(for: date), 15)
    }

    /// Snapshots written before hourly tracking have no "hours" key; they must
    /// still decode (keeping their daily totals) instead of failing the merge.
    func testDaySnapshotDecodesWithoutHours() throws {
        let json = Data(#"{"keystrokes":42,"apps":{}}"#.utf8)
        let day = try JSONDecoder().decode(DaySnapshot.self, from: json)
        XCTAssertEqual(day.keystrokes, 42)
        XCTAssertTrue(day.hours.isEmpty)
    }

    func testDaySnapshotRoundTripsHours() throws {
        let original = DaySnapshot(keystrokes: 10, apps: [:], hours: ["9": 4, "14": 6])
        let decoded = try JSONDecoder().decode(
            DaySnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.hours, ["9": 4, "14": 6])
    }
}
