import Foundation

/// The write side of `LaunchdService`: turning a job on or off, and running it
/// once on demand.
///
/// The command sequences come from what `launchctl` actually accepts, which is
/// less obvious than the man page suggests:
/// - `disable` alone leaves an already-loaded job in the domain, so stopping a
///   job means `bootout` *and* `disable` (the latter is what survives a reboot).
/// - `bootstrap` fails outright while a job is disabled, so starting one means
///   `enable` first.
/// - `kickstart` only works on a job that is currently in the domain.
extension LaunchdService {
    enum ControlError: LocalizedError {
        case missingPlist
        case disabled
        case commandFailed(command: String, status: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .missingPlist:
                return "找不到该任务的 plist 文件,无法加载它。"
            case .disabled:
                return "该任务已停用,请先启用再执行。"
            case .commandFailed(let command, let status, let output):
                let detail = output.isEmpty ? "退出码 \(status)" : output
                return "launchctl \(command) 失败:\(detail)"
            }
        }
    }

    /// `true` puts the job back in the domain and clears the persistent disable
    /// flag; `false` takes it out of the domain and disables it across reboots.
    static func setEnabled(_ enabled: Bool, job: LaunchdJob) throws -> String {
        let target = "\(userDomain)/\(job.label)"

        if enabled {
            try require(launchctl(["enable", target]), command: "enable")
            guard !job.isLoaded else { return "已启用(此前已在运行域中)" }
            guard let plistPath = job.plistPath else { throw ControlError.missingPlist }
            try require(launchctl(["bootstrap", userDomain, plistPath]), command: "bootstrap")
            return "已启用并加载"
        }

        // Not loaded is a fine starting point for disabling, so tolerate ESRCH.
        let bootout = launchctl(["bootout", target])
        if !bootout.succeeded, bootout.status != 3 {
            throw ControlError.commandFailed(
                command: "bootout",
                status: bootout.status,
                output: bootout.output
            )
        }
        try require(launchctl(["disable", target]), command: "disable")
        return "已停用"
    }

    /// Runs the job now, without waiting for its trigger.
    ///
    /// A job that is not currently loaded has to be bootstrapped first —
    /// `kickstart` cannot reach it otherwise — which leaves it loaded
    /// afterwards, so the caller says as much.
    static func runOnce(job: LaunchdJob) throws -> String {
        guard !job.isDisabled else { throw ControlError.disabled }

        var loadedForRun = false
        if !job.isLoaded {
            guard let plistPath = job.plistPath else { throw ControlError.missingPlist }
            try require(launchctl(["bootstrap", userDomain, plistPath]), command: "bootstrap")
            loadedForRun = true
        }

        try require(launchctl(["kickstart", "\(userDomain)/\(job.label)"]), command: "kickstart")
        if job.pid != nil { return "该任务本来就在运行中,launchd 未再启动一个实例" }
        return loadedForRun ? "已加载并执行一次" : "已执行一次"
    }

    private static func require(_ result: CommandResult, command: String) throws {
        guard !result.succeeded else { return }
        throw ControlError.commandFailed(
            command: command,
            status: result.status,
            output: result.output
        )
    }
}
