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
    func measure() async throws -> NetworkQualityResult {
        let processBox = ProcessBox()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = processBox.process

        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        process.arguments = ["-c", "-M", "20"]
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
