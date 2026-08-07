import Foundation

@MainActor
final class NetworkSpeedTestModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case testing
        case completed
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var result: NetworkQualityResult?
    @Published private(set) var errorMessage: String?

    private let service = NetworkSpeedTestService()
    private var testTask: Task<Void, Never>?
    private var runID = UUID()

    var isRunning: Bool {
        phase == .testing
    }

    func start(durationSeconds: Int) {
        cancel()
        let currentRunID = UUID()
        runID = currentRunID
        errorMessage = nil
        phase = .testing
        let service = service

        testTask = Task { [weak self] in
            do {
                let result = try await service.measure(durationSeconds: durationSeconds)
                guard self?.runID == currentRunID else { return }
                self?.result = result
                self?.phase = .completed
                self?.testTask = nil
            } catch {
                guard self?.runID == currentRunID else { return }
                if Task.isCancelled {
                    self?.phase = .idle
                } else {
                    self?.errorMessage = error.localizedDescription
                    self?.phase = .failed
                }
                self?.testTask = nil
            }
        }
    }

    func cancel() {
        runID = UUID()
        testTask?.cancel()
        testTask = nil
        phase = .idle
        errorMessage = nil
    }

    deinit {
        testTask?.cancel()
    }
}
