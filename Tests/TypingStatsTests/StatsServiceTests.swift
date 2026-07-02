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
}
