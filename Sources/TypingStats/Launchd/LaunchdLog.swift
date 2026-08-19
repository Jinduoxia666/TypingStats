import Foundation

/// The tail of one file a job redirects its output into.
struct LaunchdLogFile: Identifiable, Equatable {
    let path: String
    let roles: [String]
    let exists: Bool
    let byteSize: Int64
    let modifiedAt: Date?
    let tail: String
    /// The file was longer than what was read, so the first line shown is not
    /// the beginning of the log.
    let isTruncated: Bool
    let failure: String?

    var id: String { path }

    var roleTitle: String {
        roles.joined(separator: " / ")
    }
}

/// Reads the end of a job's `StandardOutPath` / `StandardErrorPath` files.
///
/// launchd keeps no log of its own for a job's output — whatever the plist does
/// not redirect is discarded — so these files are the whole story.
enum LaunchdLogReader {
    static let maxBytes = 64 * 1024
    static let maxLines = 400

    static func files(for job: LaunchdJob) -> [LaunchdLogFile] {
        job.logPaths.map { read(path: $0.path, roles: $0.roles) }
    }

    static func read(path: String, roles: [String]) -> LaunchdLogFile {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = attributes?[.modificationDate] as? Date

        guard attributes != nil else {
            return LaunchdLogFile(
                path: path,
                roles: roles,
                exists: false,
                byteSize: 0,
                modifiedAt: nil,
                tail: "",
                isTruncated: false,
                failure: nil
            )
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            return LaunchdLogFile(
                path: path,
                roles: roles,
                exists: true,
                byteSize: size,
                modifiedAt: modifiedAt,
                tail: "",
                isTruncated: false,
                failure: "没有读取该文件的权限"
            )
        }
        defer { try? handle.close() }

        let offset = max(0, size - Int64(maxBytes))
        if offset > 0 {
            try? handle.seek(toOffset: UInt64(offset))
        }
        let data = (try? handle.readToEnd()) ?? Data()
        var text = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)

        // A byte-offset seek lands mid-line; drop that fragment.
        var truncated = offset > 0
        if truncated, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }

        var lines = text.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
            truncated = true
        }

        return LaunchdLogFile(
            path: path,
            roles: roles,
            exists: true,
            byteSize: size,
            modifiedAt: modifiedAt,
            tail: lines.joined(separator: "\n"),
            isTruncated: truncated,
            failure: nil
        )
    }
}
