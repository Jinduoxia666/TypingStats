import Darwin
import XCTest
@testable import TypingStats

final class MemoryStatsReaderTests: XCTestCase {
    func testRepeatedReadsDoNotLeakHostPortReferences() throws {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        let reader = MemoryStatsReader()
        XCTAssertNotNil(reader.read())
        let before = try sendReferences(to: host)
        var successfulReads = 0
        for _ in 0..<1_000 {
            if reader.read() != nil { successfulReads += 1 }
        }

        XCTAssertEqual(successfulReads, 1_000)
        XCTAssertEqual(try sendReferences(to: host), before)
    }

    private func sendReferences(to port: mach_port_t) throws -> mach_port_urefs_t {
        var references: mach_port_urefs_t = 0
        let result = mach_port_get_refs(
            mach_task_self_, port, mach_port_right_t(MACH_PORT_RIGHT_SEND), &references
        )
        guard result == KERN_SUCCESS else {
            throw NSError(domain: NSMachErrorDomain, code: Int(result))
        }
        return references
    }
}
