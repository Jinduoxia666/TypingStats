import Foundation

@MainActor
final class LaunchdJobsModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case user
        case all
        case running
        case scheduled

        var id: String { rawValue }

        var title: String {
            switch self {
            case .user: return "我的"
            case .all: return "全部"
            case .running: return "运行中"
            case .scheduled: return "定时"
            }
        }
    }

    @Published private(set) var jobs: [LaunchdJob] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefresh: Date?
    @Published var filter: Filter = .user
    @Published var searchText = ""
    /// Drives the "下次触发" countdown without re-reading launchd.
    @Published private(set) var now = Date()
    /// Label of the job whose enable/disable/run is still in flight.
    @Published private(set) var busyLabel: String?
    @Published private(set) var actionResult: ActionResult?

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let jobs = await Task.detached(priority: .userInitiated) {
                LaunchdService.loadJobs()
            }.value
            self.jobs = jobs
            self.lastRefresh = Date()
            self.now = Date()
            self.isLoading = false
        }
    }

    func refreshIfNeeded() {
        guard jobs.isEmpty, !isLoading else { return }
        refresh()
    }

    func tick() {
        now = Date()
    }

    /// Apple's own agents are several hundred of the ~550 entries and nobody
    /// manages them by hand, so they never reach the list.
    static func isAppleSystemJob(_ job: LaunchdJob) -> Bool {
        job.label.hasPrefix("com.apple.")
    }

    var hiddenAppleJobCount: Int {
        jobs.filter(Self.isAppleSystemJob).count
    }

    var filteredJobs: [LaunchdJob] {
        let matchesFilter = jobs.filter { job in
            guard !Self.isAppleSystemJob(job) else { return false }
            switch filter {
            case .user: return job.source == .user
            case .all: return true
            case .running: return job.pid != nil
            case .scheduled:
                return !job.schedule.calendarIntervals.isEmpty || job.schedule.startInterval != nil
            }
        }

        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return matchesFilter }
        return matchesFilter.filter { job in
            job.label.localizedCaseInsensitiveContains(keyword)
                || job.programSummary?.localizedCaseInsensitiveContains(keyword) == true
        }
    }

    // MARK: - Actions

    /// Result of the last enable/disable/run, kept per label so switching jobs
    /// never shows a message that belongs to another one.
    struct ActionResult: Equatable {
        let label: String
        let text: String
        let isError: Bool
    }

    func toggleEnabled(_ job: LaunchdJob) {
        perform(job) { try LaunchdService.setEnabled(job.isDisabled, job: $0) }
    }

    func runOnce(_ job: LaunchdJob) {
        perform(job) { try LaunchdService.runOnce(job: $0) }
    }

    func result(for label: String?) -> ActionResult? {
        guard let label, actionResult?.label == label else { return nil }
        return actionResult
    }

    func isBusy(_ label: String) -> Bool {
        busyLabel == label
    }

    private func perform(_ job: LaunchdJob, action: @escaping (LaunchdJob) throws -> String) {
        guard busyLabel == nil else { return }
        busyLabel = job.label
        actionResult = nil

        Task {
            let outcome: ActionResult = await Task.detached(priority: .userInitiated) {
                do {
                    return ActionResult(label: job.label, text: try action(job), isError: false)
                } catch {
                    return ActionResult(
                        label: job.label,
                        text: error.localizedDescription,
                        isError: true
                    )
                }
            }.value

            self.actionResult = outcome
            self.busyLabel = nil
            // launchd needs a beat to publish the new pid before `list` shows it.
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.refresh()
        }
    }

    func job(withLabel label: String?) -> LaunchdJob? {
        guard let label else { return nil }
        return jobs.first { $0.label == label }
    }
}
