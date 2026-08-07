import Foundation

struct NetworkQualityResult: Equatable {
    let responsivenessRPM: Double
    let idleLatencyMilliseconds: Double
    let downloadMegabitsPerSecond: Double
    let uploadMegabitsPerSecond: Double
    let downloadBytesTransferred: Int64
    let uploadBytesTransferred: Int64
    let interfaceName: String?
    let testEndpoint: String?

    var totalBytesTransferred: Int64 {
        downloadBytesTransferred + uploadBytesTransferred
    }
}

enum NetworkQualityError: LocalizedError {
    case commandFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? "Apple 网络质量测试运行失败" : message
        case .invalidOutput:
            return "无法解析 Apple 网络质量测试结果"
        }
    }
}

enum NetworkQualityParser {
    static func parse(_ data: Data) throws -> NetworkQualityResult {
        guard let output = try? JSONDecoder().decode(NetworkQualityOutput.self, from: data) else {
            throw NetworkQualityError.invalidOutput
        }

        return NetworkQualityResult(
            responsivenessRPM: output.responsiveness,
            idleLatencyMilliseconds: output.baseRTT,
            downloadMegabitsPerSecond: output.downloadThroughput / 1_000_000,
            uploadMegabitsPerSecond: output.uploadThroughput / 1_000_000,
            downloadBytesTransferred: output.downloadBytesTransferred,
            uploadBytesTransferred: output.uploadBytesTransferred,
            interfaceName: output.interfaceName,
            testEndpoint: output.testEndpoint
        )
    }
}

struct NetworkSpeedTestService {
    static let testDurationRange = 5...120
    static let defaultTestDurationSeconds = 20

    static func arguments(maxRuntimeSeconds: Int) -> [String] {
        let duration = min(max(maxRuntimeSeconds, 1), testDurationRange.upperBound)
        return ["-c", "-M", String(duration)]
    }

    static func aggregate(_ results: [NetworkQualityResult]) throws -> NetworkQualityResult {
        guard let lastResult = results.last else {
            throw NetworkQualityError.invalidOutput
        }

        let count = Double(results.count)
        return NetworkQualityResult(
            responsivenessRPM: results.reduce(0) { $0 + $1.responsivenessRPM } / count,
            idleLatencyMilliseconds: results.reduce(0) { $0 + $1.idleLatencyMilliseconds } / count,
            downloadMegabitsPerSecond: results.reduce(0) { $0 + $1.downloadMegabitsPerSecond } / count,
            uploadMegabitsPerSecond: results.reduce(0) { $0 + $1.uploadMegabitsPerSecond } / count,
            downloadBytesTransferred: results.reduce(0) { $0 + $1.downloadBytesTransferred },
            uploadBytesTransferred: results.reduce(0) { $0 + $1.uploadBytesTransferred },
            interfaceName: lastResult.interfaceName,
            testEndpoint: lastResult.testEndpoint
        )
    }

    func measure(durationSeconds: Int) async throws -> NetworkQualityResult {
        let duration = min(
            max(durationSeconds, Self.testDurationRange.lowerBound),
            Self.testDurationRange.upperBound
        )
        let deadline = Date().addingTimeInterval(TimeInterval(duration))
        var results: [NetworkQualityResult] = []

        while Date() < deadline {
            try Task.checkCancellation()
            let remainingSeconds = max(1, Int(ceil(deadline.timeIntervalSinceNow)))

            do {
                results.append(try await measureOnce(maxRuntimeSeconds: remainingSeconds))
            } catch {
                if !results.isEmpty, Date() >= deadline {
                    break
                }
                throw error
            }
        }

        return try Self.aggregate(results)
    }

    private func measureOnce(maxRuntimeSeconds: Int) async throws -> NetworkQualityResult {
        let processBox = ProcessBox()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = processBox.process

        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        process.arguments = Self.arguments(maxRuntimeSeconds: maxRuntimeSeconds)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let output = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, Error>) in
                process.terminationHandler = { finishedProcess in
                    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    guard finishedProcess.terminationStatus == 0 else {
                        let message = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(throwing: NetworkQualityError.commandFailed(message))
                        return
                    }

                    continuation.resume(returning: output)
                }

                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            processBox.terminate()
        }

        try Task.checkCancellation()
        return try NetworkQualityParser.parse(output)
    }
}

private struct NetworkQualityOutput: Decodable {
    let responsiveness: Double
    let baseRTT: Double
    let downloadThroughput: Double
    let uploadThroughput: Double
    let downloadBytesTransferred: Int64
    let uploadBytesTransferred: Int64
    let interfaceName: String?
    let testEndpoint: String?

    enum CodingKeys: String, CodingKey {
        case responsiveness
        case baseRTT = "base_rtt"
        case downloadThroughput = "dl_throughput"
        case uploadThroughput = "ul_throughput"
        case downloadBytesTransferred = "dl_bytes_transferred"
        case uploadBytesTransferred = "ul_bytes_transferred"
        case interfaceName = "interface_name"
        case testEndpoint = "test_endpoint"
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
