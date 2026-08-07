import XCTest
@testable import TypingStats

final class NetworkQualityParserTests: XCTestCase {
    func testBuildsArgumentsWithCustomMaximumRuntime() {
        XCTAssertEqual(
            NetworkSpeedTestService.arguments(maxRuntimeSeconds: 45),
            ["-c", "-M", "45"]
        )
    }

    func testClampsCommandRuntimeToValidRange() {
        XCTAssertEqual(
            NetworkSpeedTestService.arguments(maxRuntimeSeconds: 0),
            ["-c", "-M", "1"]
        )
        XCTAssertEqual(
            NetworkSpeedTestService.arguments(maxRuntimeSeconds: 300),
            ["-c", "-M", "120"]
        )
    }

    func testAggregatesCompletedNetworkQualityRuns() throws {
        let first = NetworkQualityResult(
            responsivenessRPM: 100,
            idleLatencyMilliseconds: 20,
            downloadMegabitsPerSecond: 80,
            uploadMegabitsPerSecond: 40,
            downloadBytesTransferred: 1_000,
            uploadBytesTransferred: 500,
            interfaceName: "en0",
            testEndpoint: "first.example.com"
        )
        let second = NetworkQualityResult(
            responsivenessRPM: 200,
            idleLatencyMilliseconds: 40,
            downloadMegabitsPerSecond: 100,
            uploadMegabitsPerSecond: 60,
            downloadBytesTransferred: 2_000,
            uploadBytesTransferred: 800,
            interfaceName: "en1",
            testEndpoint: "second.example.com"
        )

        let result = try NetworkSpeedTestService.aggregate([first, second])

        XCTAssertEqual(result.responsivenessRPM, 150)
        XCTAssertEqual(result.idleLatencyMilliseconds, 30)
        XCTAssertEqual(result.downloadMegabitsPerSecond, 90)
        XCTAssertEqual(result.uploadMegabitsPerSecond, 50)
        XCTAssertEqual(result.downloadBytesTransferred, 3_000)
        XCTAssertEqual(result.uploadBytesTransferred, 1_300)
        XCTAssertEqual(result.interfaceName, "en1")
        XCTAssertEqual(result.testEndpoint, "second.example.com")
    }

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
