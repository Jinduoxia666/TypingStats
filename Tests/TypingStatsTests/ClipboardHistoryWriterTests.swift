import XCTest
@testable import TypingStats

final class ClipboardHistoryWriterTests: XCTestCase {
    private var directory: URL!
    private var storageURL: URL { directory.appendingPathComponent("history.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testBlockedQueueWritesOnlyLatestSnapshot() throws {
        let queue = DispatchQueue(label: "clipboard-writer-test")
        let unblock = DispatchSemaphore(value: 0)
        queue.async { unblock.wait() }
        var writeCount = 0
        let writer = ClipboardHistoryWriter(storageURL: storageURL, queue: queue) { data, url in
            writeCount += 1
            try data.write(to: url, options: .atomic)
        }
        var latest: [ClipboardHistoryItem] = []
        for index in 0..<100 {
            latest = [item(text: "snapshot \(index)")]
            writer.save(latest)
        }
        unblock.signal()
        queue.sync {}

        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(try readHistory(), latest)
    }

    func testUpdatesDuringWritePersistLatestSnapshot() throws {
        let latest = [item(text: "latest")]
        try assertUpdatesDuringWrite(finalItems: latest)
    }

    func testClearDuringWriteDoesNotRestoreOldHistory() throws {
        try assertUpdatesDuringWrite(finalItems: [])
    }

    func testFailedWriteDoesNotBlockLaterSaves() throws {
        let queue = DispatchQueue(label: "clipboard-writer-test")
        var writeCount = 0
        let writer = ClipboardHistoryWriter(storageURL: storageURL, queue: queue) { data, url in
            writeCount += 1
            if writeCount == 1 { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        }
        writer.save([item(text: "failed")])
        queue.sync {}
        let latest = [item(text: "saved")]
        writer.save(latest)
        queue.sync {}

        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(try readHistory(), latest)
    }

    private func assertUpdatesDuringWrite(finalItems: [ClipboardHistoryItem]) throws {
        let queue = DispatchQueue(label: "clipboard-writer-test")
        let started = DispatchSemaphore(value: 0)
        let unblock = DispatchSemaphore(value: 0)
        defer { unblock.signal() }
        var writeCount = 0
        let writer = ClipboardHistoryWriter(storageURL: storageURL, queue: queue) { data, url in
            writeCount += 1
            if writeCount == 1 {
                started.signal()
                unblock.wait()
            }
            try data.write(to: url, options: .atomic)
        }
        writer.save([item(text: "old")])
        let waitResult = started.wait(timeout: .now() + 5)
        XCTAssertEqual(waitResult, .success)
        guard waitResult == .success else { return }
        for index in 0..<100 {
            writer.save([item(text: "intermediate \(index)")])
        }
        writer.save(finalItems)
        unblock.signal()
        queue.sync {}

        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(try readHistory(), finalItems)
    }

    private func item(text: String) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: UUID(), kind: .text, createdAt: Date(), text: text,
            imageFileName: nil, thumbnailJPEGData: nil, contentHash: text
        )
    }

    private func readHistory() throws -> [ClipboardHistoryItem] {
        try JSONDecoder().decode([ClipboardHistoryItem].self, from: Data(contentsOf: storageURL))
    }
}
