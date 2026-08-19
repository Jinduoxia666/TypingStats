import XCTest
@testable import TypingStats

final class LaunchdScheduleTests: XCTestCase {
    /// Fixed UTC calendar so the expected timestamps don't move with the host.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    private func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    func testParsesArrayOfCalendarIntervals() {
        let schedule = LaunchdSchedule(plist: [
            "StartCalendarInterval": [
                ["Minute": 10],
                ["Minute": 30],
                ["Minute": 50],
            ],
        ])

        XCTAssertEqual(schedule.calendarIntervals.count, 3)
        XCTAssertEqual(schedule.calendarIntervals.map(\.minute), [10, 30, 50])
    }

    func testParsesSingleCalendarIntervalDictionary() {
        let schedule = LaunchdSchedule(plist: [
            "StartCalendarInterval": ["Hour": 9, "Minute": 5],
            "RunAtLoad": true,
        ])

        XCTAssertEqual(schedule.calendarIntervals, [LaunchdCalendarInterval(minute: 5, hour: 9)])
        XCTAssertTrue(schedule.runAtLoad)
    }

    func testHourOnlyIntervalFiresOnTheHour() {
        let interval = LaunchdCalendarInterval(hour: 9)
        let next = LaunchdSchedule.nextFireDate(
            for: interval,
            after: date("2026-08-19 09:30:00"),
            calendar: calendar
        )

        XCTAssertEqual(next.map(text), "2026-08-20 09:00:00")
    }

    func testMinuteOnlyIntervalFiresEveryHour() {
        let interval = LaunchdCalendarInterval(minute: 30)
        let next = LaunchdSchedule.nextFireDate(
            for: interval,
            after: date("2026-08-19 09:31:00"),
            calendar: calendar
        )

        XCTAssertEqual(next.map(text), "2026-08-19 10:30:00")
    }

    func testWeekdayZeroAndSevenBothMeanSunday() {
        XCTAssertEqual(LaunchdCalendarInterval.calendarWeekday(fromLaunchd: 0), 1)
        XCTAssertEqual(LaunchdCalendarInterval.calendarWeekday(fromLaunchd: 7), 1)
        XCTAssertEqual(LaunchdCalendarInterval.calendarWeekday(fromLaunchd: 1), 2)

        // 2026-08-19 is a Wednesday, so the next Sunday is the 23rd.
        let next = LaunchdSchedule.nextFireDate(
            for: LaunchdCalendarInterval(hour: 3, weekday: 0),
            after: date("2026-08-19 09:00:00"),
            calendar: calendar
        )
        XCTAssertEqual(next.map(text), "2026-08-23 03:00:00")
    }

    func testDayOfMonthIntervalFiresAtMidnight() {
        let next = LaunchdSchedule.nextFireDate(
            for: LaunchdCalendarInterval(day: 1),
            after: date("2026-08-19 09:00:00"),
            calendar: calendar
        )

        XCTAssertEqual(next.map(text), "2026-09-01 00:00:00")
    }

    func testEarliestOfSeveralIntervalsWins() {
        var schedule = LaunchdSchedule()
        schedule.calendarIntervals = [
            LaunchdCalendarInterval(minute: 50),
            LaunchdCalendarInterval(minute: 10),
            LaunchdCalendarInterval(minute: 30),
        ]

        let next = schedule.nextFireDate(after: date("2026-08-19 09:15:00"), calendar: calendar)
        XCTAssertEqual(next.map(text), "2026-08-19 09:30:00")
    }

    func testIntervalOnlyScheduleHasNoKnownNextFireDate() {
        let schedule = LaunchdSchedule(plist: ["StartInterval": 3_600])

        XCTAssertEqual(schedule.startInterval, 3_600)
        XCTAssertNil(schedule.nextFireDate(after: date("2026-08-19 09:15:00"), calendar: calendar))
        XCTAssertEqual(schedule.descriptions, ["每隔 1 小时"])
    }

    func testKeepAliveDictionaryCountsAsKeepAlive() {
        let schedule = LaunchdSchedule(plist: ["KeepAlive": ["SuccessfulExit": false]])
        XCTAssertTrue(schedule.keepAlive)

        let disabled = LaunchdSchedule(plist: ["KeepAlive": false])
        XCTAssertFalse(disabled.keepAlive)
    }

    func testDescribesOnDemandJobsWithoutTriggers() {
        XCTAssertEqual(LaunchdSchedule(plist: [:]).descriptions, ["按需 / 未声明触发条件"])
    }

    func testDurationTextUsesLargestWholeUnit() {
        XCTAssertEqual(LaunchdSchedule.durationText(seconds: 45), "45 秒")
        XCTAssertEqual(LaunchdSchedule.durationText(seconds: 300), "5 分钟")
        XCTAssertEqual(LaunchdSchedule.durationText(seconds: 7_200), "2 小时")
        XCTAssertEqual(LaunchdSchedule.durationText(seconds: 432_000), "5 天")
    }

    func testDisabledJobReportsNoNextFireDate() {
        var schedule = LaunchdSchedule()
        schedule.calendarIntervals = [LaunchdCalendarInterval(minute: 0, hour: 9)]
        let job = LaunchdJob(
            label: "com.example.job",
            source: .user,
            plistPath: "/tmp/com.example.job.plist",
            pid: nil,
            lastExitStatus: 0,
            isLoaded: true,
            isDisabled: true,
            schedule: schedule,
            configuration: [],
            programSummary: "/usr/bin/true"
        )

        XCTAssertNil(job.nextFireDate(after: date("2026-08-19 09:15:00")))
        XCTAssertEqual(job.statusText, "已停用")
    }
}
