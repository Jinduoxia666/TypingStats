import XCTest
@testable import TypingStats

final class TimestampViewModelTests: XCTestCase {
    @MainActor
    func testStopInvalidatesTimer() async throws {
        let model = TimestampViewModel()
        model.start()
        let timer = try currentTimer(in: model)
        defer { timer.invalidate() }

        model.stop()

        XCTAssertFalse(timer.isValid)
    }

    @MainActor
    func testRestartInvalidatesPreviousTimer() async throws {
        let model = TimestampViewModel()
        model.start()
        let previousTimer = try currentTimer(in: model)
        defer {
            previousTimer.invalidate()
            model.stop()
        }

        model.start()

        XCTAssertFalse(previousTimer.isValid)
        XCTAssertTrue(try currentTimer(in: model).isValid)
    }

    @MainActor
    func testDeinitInvalidatesTimer() async throws {
        weak var releasedModel: TimestampViewModel?
        let timer = try autoreleasepool {
            let model = TimestampViewModel()
            releasedModel = model
            model.start()
            return try currentTimer(in: model)
        }
        defer { timer.invalidate() }

        XCTAssertNil(releasedModel)
        XCTAssertFalse(timer.isValid)
    }

    @MainActor
    private func currentTimer(in model: TimestampViewModel) throws -> Timer {
        // Inspect the actual resource without exposing a timer in the app's API.
        try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "timer" }?.value as? Timer)
    }
}
