import XCTest
@testable import TypingStats

final class NetworkQualityParserTests: XCTestCase {
    func testParsesAppleNetworkQualityOutput() throws {
        let data = Data(
            """
            {
              "base_rtt": 196.3685,
              "dl_bytes_transferred": 83818429,
              "dl_throughput": 83501696,
              "interface_name": "utun1024",
              "responsiveness": 142.048,
              "test_endpoint": "hkhkg1-edge-fx-014.aaplimg.com",
              "ul_bytes_transferred": 84017150,
              "ul_throughput": 82404912
            }
            """.utf8
        )

        let result = try NetworkQualityParser.parse(data)

        XCTAssertEqual(result.responsivenessRPM, 142.048, accuracy: 0.0001)
        XCTAssertEqual(result.idleLatencyMilliseconds, 196.3685, accuracy: 0.0001)
        XCTAssertEqual(result.downloadMegabitsPerSecond, 83.501696, accuracy: 0.0001)
        XCTAssertEqual(result.uploadMegabitsPerSecond, 82.404912, accuracy: 0.0001)
        XCTAssertEqual(result.downloadBytesTransferred, 83_818_429)
        XCTAssertEqual(result.uploadBytesTransferred, 84_017_150)
        XCTAssertEqual(result.totalBytesTransferred, 167_835_579)
        XCTAssertEqual(result.interfaceName, "utun1024")
        XCTAssertEqual(result.testEndpoint, "hkhkg1-edge-fx-014.aaplimg.com")
    }

    func testRejectsIncompleteOutput() {
        XCTAssertThrowsError(try NetworkQualityParser.parse(Data("{}".utf8)))
    }
}
