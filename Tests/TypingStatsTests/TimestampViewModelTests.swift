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

    func testFrameOriginNearCursorPositionsWhenInsideVisibleScreen() {
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let mouseLocation = NSPoint(x: 200, y: 600)
        let windowSize = NSSize(width: 500, height: 374)

        let origin = TimestampWindowController.frameOriginNearCursor(
            mouseLocation: mouseLocation,
            windowSize: windowSize,
            in: visibleFrame
        )

        XCTAssertEqual(origin, NSPoint(x: 212, y: 214))
    }

    func testFrameOriginNearCursorClampsToBottomAndRightVisibleEdges() {
        let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let mouseLocation = NSPoint(x: 1300, y: 120)
        let windowSize = NSSize(width: 500, height: 374)

        let origin = TimestampWindowController.frameOriginNearCursor(
            mouseLocation: mouseLocation,
            windowSize: windowSize,
            in: visibleFrame
        )

        XCTAssertEqual(origin, NSPoint(x: 928, y: 37))
    }

    func testFrameOriginNearCursorSupportsNegativeSecondaryDisplayCoordinates() {
        let visibleFrame = NSRect(x: -1920, y: 0, width: 1920, height: 1055)
        let mouseLocation = NSPoint(x: -1600, y: 600)
        let windowSize = NSSize(width: 500, height: 374)

        let origin = TimestampWindowController.frameOriginNearCursor(
            mouseLocation: mouseLocation,
            windowSize: windowSize,
            in: visibleFrame
        )

        XCTAssertEqual(origin, NSPoint(x: -1588, y: 214))

        let clampedOrigin = TimestampWindowController.frameOriginNearCursor(
            mouseLocation: NSPoint(x: -2000, y: 1000),
            windowSize: windowSize,
            in: visibleFrame
        )

        XCTAssertEqual(clampedOrigin, NSPoint(x: -1908, y: 614))
    }

    func testExtractConvertibleInputHandlesTimestampsQuotesAndInvalidText() {
        XCTAssertEqual(TimestampConversionItem.extractConvertibleInput("1795829421"), "1795829421")
        XCTAssertEqual(TimestampConversionItem.extractConvertibleInput("  1795829421000 \n"), "1795829421000")
        XCTAssertEqual(TimestampConversionItem.extractConvertibleInput("\"1795829421\","), "1795829421")
        XCTAssertEqual(TimestampConversionItem.extractConvertibleInput("'2026-11-28 10:51:07';"), "2026-11-28 10:51:07")
        XCTAssertNil(TimestampConversionItem.extractConvertibleInput("order.status.push"))
        XCTAssertNil(TimestampConversionItem.extractConvertibleInput("   "))
    }

    func testKeyActionClosesOnEscapeAndCommandW() {
        XCTAssertEqual(
            TimestampWindowController.keyAction(
                keyCode: 53,
                modifierFlags: [],
                charactersIgnoringModifiers: nil,
                hasMarkedText: false
            ),
            .close
        )
        XCTAssertEqual(
            TimestampWindowController.keyAction(
                keyCode: 13,
                modifierFlags: [.command],
                charactersIgnoringModifiers: "w",
                hasMarkedText: false
            ),
            .close
        )
    }

    func testKeyActionHandlesNavigationConfirmAndMarkedText() {
        XCTAssertEqual(
            TimestampWindowController.keyAction(
                keyCode: 125,
                modifierFlags: [],
                charactersIgnoringModifiers: nil,
                hasMarkedText: false
            ),
            .moveSelection(1)
        )
        XCTAssertEqual(
            TimestampWindowController.keyAction(
                keyCode: 126,
                modifierFlags: [],
                charactersIgnoringModifiers: nil,
                hasMarkedText: false
            ),
            .moveSelection(-1)
        )
        XCTAssertEqual(
            TimestampWindowController.keyAction(
                keyCode: 36,
                modifierFlags: [],
                charactersIgnoringModifiers: nil,
                hasMarkedText: false
            ),
            .confirmSelection
        )
        XCTAssertEqual(
            TimestampWindowController.keyAction(
                keyCode: 76,
                modifierFlags: [],
                charactersIgnoringModifiers: nil,
                hasMarkedText: false
            ),
            .confirmSelection
        )
        XCTAssertNil(
            TimestampWindowController.keyAction(
                keyCode: 53,
                modifierFlags: [],
                charactersIgnoringModifiers: nil,
                hasMarkedText: true
            )
        )
        XCTAssertNil(
            TimestampWindowController.keyAction(
                keyCode: 36,
                modifierFlags: [],
                charactersIgnoringModifiers: nil,
                hasMarkedText: true
            )
        )
    }
}
