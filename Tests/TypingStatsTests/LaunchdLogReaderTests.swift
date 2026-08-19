import XCTest
@testable import TypingStats

final class LaunchdLogReaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LaunchdLogReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ contents: String, name: String = "job.log") throws -> String {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testReadsWholeShortLog() throws {
        let path = try write("first\nsecond\nthird\n")
        let file = LaunchdLogReader.read(path: path, roles: ["标准输出"])

        XCTAssertTrue(file.exists)
        XCTAssertNil(file.failure)
        XCTAssertFalse(file.isTruncated)
        XCTAssertEqual(file.tail, "first\nsecond\nthird")
    }

    func testKeepsOnlyTheLastLines() throws {
        let lines = (1...1_000).map { "line \($0)" }
        let path = try write(lines.joined(separator: "\n") + "\n")
        let file = LaunchdLogReader.read(path: path, roles: ["标准输出"])

        let tail = file.tail.components(separatedBy: "\n")
        XCTAssertEqual(tail.count, LaunchdLogReader.maxLines)
        XCTAssertEqual(tail.last, "line 1000")
        XCTAssertEqual(tail.first, "line \(1_000 - LaunchdLogReader.maxLines + 1)")
        XCTAssertTrue(file.isTruncated)
    }

    /// Seeking by byte offset lands mid-line; that fragment must not be shown.
    func testDropsThePartialFirstLineOfALargeLog() throws {
        let line = String(repeating: "x", count: 200)
        let lines = (1...1_000).map { "\($0) \(line)" }
        let path = try write(lines.joined(separator: "\n") + "\n")
        let file = LaunchdLogReader.read(path: path, roles: ["标准错误"])

        XCTAssertGreaterThan(file.byteSize, Int64(LaunchdLogReader.maxBytes))
        XCTAssertTrue(file.isTruncated)
        for entry in file.tail.components(separatedBy: "\n") {
            XCTAssertTrue(
                entry.hasSuffix(line),
                "每一行都应该是完整的一行,而不是被字节偏移切断的片段"
            )
        }
    }

    func testMissingFileIsReportedWithoutFailure() {
        let file = LaunchdLogReader.read(
            path: directory.appendingPathComponent("never-written.log").path,
            roles: ["标准输出"]
        )

        XCTAssertFalse(file.exists)
        XCTAssertNil(file.failure)
        XCTAssertTrue(file.tail.isEmpty)
    }

    func testMergesRolesWhenStdoutAndStderrShareAFile() {
        var job = LaunchdJob(
            label: "com.example.job",
            source: .user,
            plistPath: nil,
            pid: nil,
            lastExitStatus: nil,
            isLoaded: true,
            isDisabled: false,
            schedule: LaunchdSchedule(),
            configuration: [],
            programSummary: nil
        )
        job.standardOutPath = "/tmp/shared.log"
        job.standardErrorPath = "/tmp/shared.log"

        XCTAssertEqual(job.logPaths.count, 1)
        XCTAssertEqual(job.logPaths.first?.roles, ["标准输出", "标准错误"])

        job.standardErrorPath = "/tmp/other.log"
        XCTAssertEqual(job.logPaths.map(\.path), ["/tmp/shared.log", "/tmp/other.log"])
    }

    func testExpandsTildeInLogPaths() {
        var job = LaunchdJob(
            label: "com.example.job",
            source: .user,
            plistPath: nil,
            pid: nil,
            lastExitStatus: nil,
            isLoaded: true,
            isDisabled: false,
            schedule: LaunchdSchedule(),
            configuration: [],
            programSummary: nil
        )
        job.standardOutPath = "~/Library/Logs/example.log"

        XCTAssertEqual(
            job.logPaths.first?.path,
            (("~/Library/Logs/example.log") as NSString).expandingTildeInPath
        )
    }
}
