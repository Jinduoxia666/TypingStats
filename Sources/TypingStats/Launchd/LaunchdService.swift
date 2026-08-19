import Foundation

/// Reads the user's launchd domain (`gui/$UID`): what is loaded right now, plus
/// every LaunchAgent plist on disk — including ones that are not loaded, which
/// `launchctl` alone would never mention.
///
/// Also the write side: enabling/disabling a job and running it once. Those go
/// through `launchctl` exactly as they would in a terminal — nothing here edits
/// a plist or touches launchd's databases directly.
enum LaunchdService {
    static var userDomain: String { "gui/\(getuid())" }

    static func loadJobs() -> [LaunchdJob] {
        let loaded = loadedServices()
        let disabled = disabledServices()
        var plists = agentPlists()

        var jobs: [LaunchdJob] = []

        for service in loaded {
            let plist = plists.removeValue(forKey: service.label)
            jobs.append(makeJob(
                label: service.label,
                plist: plist,
                pid: service.pid,
                lastExitStatus: service.lastExitStatus,
                isLoaded: true,
                isDisabled: disabled[service.label] ?? false
            ))
        }

        // Whatever is left has a plist but is not in the domain right now.
        for (label, plist) in plists {
            jobs.append(makeJob(
                label: label,
                plist: plist,
                pid: nil,
                lastExitStatus: nil,
                isLoaded: false,
                isDisabled: disabled[label] ?? false
            ))
        }

        return jobs.sorted { lhs, rhs in
            if lhs.source != rhs.source { return lhs.source < rhs.source }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    /// `launchctl print gui/$UID/<label>` — the live view launchd itself keeps,
    /// which is the only place things like the resolved program path and event
    /// triggers of a plist-less service show up.
    static func printOutput(label: String) -> String {
        let result = launchctl(["print", "\(userDomain)/\(label)"])
        let text = result.output
        return text.isEmpty ? "launchctl 没有返回内容。" : text
    }

    static func plistText(at path: String) -> String? {
        if let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        // Binary plists: round-trip them through the XML representation.
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let xml = try? PropertyListSerialization.data(
                  fromPropertyList: object,
                  format: .xml,
                  options: 0
              ) else { return nil }
        return String(data: xml, encoding: .utf8)
    }

    // MARK: - Sources

    private struct LoadedService {
        let label: String
        let pid: Int?
        let lastExitStatus: Int?
    }

    /// `launchctl list` rows: `PID\tStatus\tLabel`, with `-` for "none".
    private static func loadedServices() -> [LoadedService] {
        launchctl(["list"]).output
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let columns = line.components(separatedBy: "\t")
                guard columns.count >= 3, !columns[2].isEmpty else { return nil }
                return LoadedService(
                    label: columns[2],
                    pid: Int(columns[0]),
                    lastExitStatus: Int(columns[1])
                )
            }
    }

    /// `launchctl print-disabled gui/$UID` rows: `"label" => disabled`.
    private static func disabledServices() -> [String: Bool] {
        var result: [String: Bool] = [:]
        for line in launchctl(["print-disabled", userDomain]).output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            guard !label.isEmpty else { continue }
            result[label] = parts[1].contains("disabled")
        }
        return result
    }

    private struct AgentPlist {
        let source: LaunchdJobSource
        let path: String
        let contents: [String: Any]
    }

    private static func agentPlists() -> [String: AgentPlist] {
        var result: [String: AgentPlist] = [:]
        // Later directories must not shadow earlier ones: a user agent wins over
        // a system agent that happens to reuse the label.
        for source in [LaunchdJobSource.user, .global, .system] {
            guard let directory = source.directoryURL,
                  let files = try? FileManager.default.contentsOfDirectory(
                      at: directory,
                      includingPropertiesForKeys: nil
                  ) else { continue }

            for file in files where file.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: file),
                      let contents = try? PropertyListSerialization.propertyList(
                          from: data,
                          format: nil
                      ) as? [String: Any] else { continue }
                let label = contents["Label"] as? String ?? file.deletingPathExtension().lastPathComponent
                guard result[label] == nil else { continue }
                result[label] = AgentPlist(source: source, path: file.path, contents: contents)
            }
        }
        return result
    }

    // MARK: - Assembly

    private static func makeJob(
        label: String,
        plist: AgentPlist?,
        pid: Int?,
        lastExitStatus: Int?,
        isLoaded: Bool,
        isDisabled: Bool
    ) -> LaunchdJob {
        let contents = plist?.contents ?? [:]
        return LaunchdJob(
            label: label,
            source: plist?.source ?? .unmanaged,
            plistPath: plist?.path,
            pid: pid,
            lastExitStatus: lastExitStatus,
            isLoaded: isLoaded,
            isDisabled: isDisabled || (contents["Disabled"] as? NSNumber)?.boolValue == true,
            schedule: LaunchdSchedule(plist: contents),
            configuration: configurationEntries(from: contents),
            programSummary: programSummary(from: contents),
            standardOutPath: contents["StandardOutPath"] as? String,
            standardErrorPath: contents["StandardErrorPath"] as? String
        )
    }

    private static func programSummary(from plist: [String: Any]) -> String? {
        if let arguments = plist["ProgramArguments"] as? [String], !arguments.isEmpty {
            return arguments.joined(separator: " ")
        }
        return plist["Program"] as? String
    }

    private static func configurationEntries(from plist: [String: Any]) -> [LaunchdConfigEntry] {
        plist.keys.sorted().map { key in
            LaunchdConfigEntry(key: key, value: describe(plist[key] ?? "", indent: 0))
        }
    }

    /// Flattens a plist value into indented text — good enough to read a job's
    /// whole configuration without scrolling through raw XML.
    private static func describe(_ value: Any, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent + 1)
        switch value {
        case let dictionary as [String: Any]:
            guard !dictionary.isEmpty else { return "{}" }
            return "\n" + dictionary.keys.sorted().map { key in
                "\(pad)\(key): \(describe(dictionary[key] ?? "", indent: indent + 1))"
            }.joined(separator: "\n")
        case let array as [Any]:
            guard !array.isEmpty else { return "[]" }
            return "\n" + array.map { "\(pad)· \(describe($0, indent: indent + 1))" }.joined(separator: "\n")
        case let number as NSNumber:
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let data as Data:
            return "<\(data.count) 字节>"
        default:
            return String(describing: value)
        }
    }

    struct CommandResult {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            output: (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @discardableResult
    static func launchctl(_ arguments: [String]) -> CommandResult {
        run("/bin/launchctl", arguments)
    }
}
