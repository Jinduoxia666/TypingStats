import SwiftUI
import AppKit

/// Read-only browser for the user launchd domain (`gui/$UID`): every agent that
/// is loaded plus every LaunchAgent plist on disk, with one job's full
/// configuration and its next trigger time on the right.
struct LaunchdView: View {
    var isActive: Bool = true

    @StateObject private var model = LaunchdJobsModel()
    @State private var selection: String?
    private let clockTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        if isActive {
            content
        } else {
            Color.clear
        }
    }

    private var content: some View {
        HSplitView {
            jobList
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            detailPane
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            model.refreshIfNeeded()
        }
        .onReceive(clockTimer) { _ in
            model.tick()
        }
        .onChange(of: model.filter) { _ in
            selectFirstIfNeeded()
        }
        .onChange(of: model.searchText) { _ in
            selectFirstIfNeeded()
        }
        .onChange(of: model.jobs) { _ in
            selectFirstIfNeeded()
        }
    }

    // MARK: - List

    private var jobList: some View {
        VStack(spacing: 8) {
            Picker("", selection: $model.filter) {
                ForEach(LaunchdJobsModel.Filter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("搜索标签或程序", text: $model.searchText)
                .textFieldStyle(.roundedBorder)

            List(model.filteredJobs, selection: $selection) { job in
                jobRow(job)
                    .tag(job.label)
            }
            .listStyle(.inset)

            HStack {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoading)
            }
        }
        .padding(10)
    }

    private func jobRow(_ job: LaunchdJob) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(job))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(rowSubtitle(job))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func rowSubtitle(_ job: LaunchdJob) -> String {
        if let next = job.nextFireDate(after: model.now) {
            return "下次 " + Self.shortFormatter.string(from: next)
        }
        return job.schedule.descriptions.first ?? job.statusText
    }

    private func statusColor(_ job: LaunchdJob) -> Color {
        if job.isDisabled { return .secondary.opacity(0.5) }
        if job.pid != nil { return .green }
        if let status = job.lastExitStatus, status != 0 { return .orange }
        if job.isLoaded { return .blue.opacity(0.6) }
        return .secondary.opacity(0.4)
    }

    private var footerText: String {
        if model.isLoading { return "读取中…" }
        let hidden = model.hiddenAppleJobCount
        var text = "\(model.filteredJobs.count) / \(model.jobs.count - hidden) 项"
        if hidden > 0 {
            text += " · 已隐藏 \(hidden) 项 Apple"
        }
        if let lastRefresh = model.lastRefresh {
            text += " · " + Self.timeFormatter.string(from: lastRefresh)
        }
        return text
    }

    private func selectFirstIfNeeded() {
        let visible = model.filteredJobs
        if let selection, visible.contains(where: { $0.label == selection }) { return }
        selection = visible.first?.label
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let job = model.job(withLabel: selection) {
            ScrollView {
                LaunchdJobDetailView(job: job, model: model)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(model.isLoading ? "正在读取 launchd…" : "选择左侧的任务查看完整配置")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct LaunchdJobDetailView: View {
    let job: LaunchdJob
    @ObservedObject var model: LaunchdJobsModel

    private var now: Date { model.now }

    @State private var printOutput: String?
    @State private var plistText: String?
    @State private var logFiles: [LaunchdLogFile] = []
    @State private var isLoadingLogs = false
    @State private var showsRawPlist = false
    @State private var showsPrintOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            controls
            triggerSection
            programSection
            logSection
            configurationSection
            rawSections
        }
        .textSelection(.enabled)
        .onChange(of: model.actionResult) { _ in
            // Running the job on demand is the main reason to look at its log.
            reloadLogs()
        }
        .task(id: job.label) {
            printOutput = nil
            plistText = nil
            // Never leave the previous job's log on screen while this one loads.
            logFiles = []
            reloadLogs()
            let label = job.label
            let plistPath = job.plistPath
            // Both of these hit the disk (and `launchctl print` forks a
            // process), so neither belongs on the main actor.
            plistText = await Task.detached(priority: .utility) {
                plistPath.flatMap(LaunchdService.plistText(at:))
            }.value
            printOutput = await Task.detached(priority: .utility) {
                LaunchdService.printOutput(label: label)
            }.value
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(job.label)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(2)
            HStack(spacing: 8) {
                badge(job.statusText, color: statusColor)
                badge(job.source.title, color: .secondary)
                if let status = job.lastExitStatus {
                    badge("上次退出 \(status)", color: status == 0 ? .secondary : .orange)
                }
            }
            if let path = job.plistPath {
                HStack(spacing: 10) {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } else {
                Text("没有找到对应的 plist(多为 App 内置的 XPC 服务)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        if job.isDisabled { return .secondary }
        if job.pid != nil { return .green }
        return job.isLoaded ? .blue : .secondary
    }

    /// Enable/disable and run-now. Both are plain `launchctl` calls and both are
    /// reversible from this same row, so neither asks for a confirmation.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    model.toggleEnabled(job)
                } label: {
                    Label(
                        job.isDisabled ? "启用" : "停用",
                        systemImage: job.isDisabled ? "play.circle" : "pause.circle"
                    )
                }
                .disabled(!canToggle || isBusy)

                Button {
                    model.runOnce(job)
                } label: {
                    Label("立即执行一次", systemImage: "bolt.fill")
                }
                .disabled(!canRunNow || isBusy)

                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
            }

            if let result = model.result(for: job.label) {
                Label(result.text, systemImage: result.isError
                    ? "exclamationmark.triangle.fill"
                    : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(result.isError ? Color.orange : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let hint = controlHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isBusy: Bool {
        model.isBusy(job.label)
    }

    /// Re-enabling needs the plist to bootstrap from, so a job without one can
    /// only ever be stopped — better to offer neither than a one-way switch.
    private var canToggle: Bool {
        job.plistPath != nil
    }

    private var canRunNow: Bool {
        !job.isDisabled && (job.isLoaded || job.plistPath != nil)
    }

    private var controlHint: String? {
        if !canToggle {
            return "该任务没有可用的 plist(多为 App 内置服务),无法在这里启停。"
        }
        if job.isDisabled {
            return "已停用:已移出运行域并写入 launchctl disable,重启后依然不会运行。"
        }
        if !job.isLoaded {
            return "该 plist 当前未加载,「立即执行一次」会先把它加载进运行域。"
        }
        return nil
    }

    private var triggerSection: some View {
        card("触发条件", systemImage: "clock") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("下次触发")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(nextFireText)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    if let relative = nextFireRelativeText {
                        Text(relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let note = nextFireNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                ForEach(Array(job.schedule.descriptions.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "arrow.turn.down.right")
                        .font(.callout)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private var nextFireDate: Date? {
        job.nextFireDate(after: now)
    }

    private var nextFireText: String {
        if job.isDisabled { return "已停用" }
        guard let nextFireDate else { return "—" }
        return Self.fullFormatter.string(from: nextFireDate)
    }

    private var nextFireRelativeText: String? {
        guard let nextFireDate else { return nil }
        return "· " + Self.relativeFormatter.localizedString(for: nextFireDate, relativeTo: now)
    }

    /// launchd never exposes the load time an interval job counts from, so those
    /// jobs get an explanation instead of an invented timestamp.
    private var nextFireNote: String? {
        if job.isDisabled { return "该任务已被 launchctl disable 停用,不会触发。" }
        if nextFireDate != nil {
            return job.isLoaded ? nil : "该 plist 当前未加载,时间按配置推算,实际不会触发。"
        }
        if let interval = job.schedule.startInterval {
            return "按 StartInterval 每 \(LaunchdSchedule.durationText(seconds: interval)) 触发一次,起点是 launchd 加载它的时刻,系统未公开该时刻。"
        }
        return "没有固定的时间触发条件,由事件或按需启动。"
    }

    private var programSection: some View {
        card("程序", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 6) {
                if let program = job.programSummary {
                    Text(program)
                        .font(.system(.callout, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("plist 未声明 Program / ProgramArguments")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let pid = job.pid {
                    Text("PID \(pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var logSection: some View {
        card("日志", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 12) {
                if job.logPaths.isEmpty {
                    Text("该任务没有配置 StandardOutPath / StandardErrorPath,launchd 会直接丢弃它的输出。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack {
                        Text(logFiles.count > 1 ? "\(logFiles.count) 个输出文件" : "输出文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            reloadLogs()
                        } label: {
                            if isLoadingLogs {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("刷新", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(isLoadingLogs)
                    }
                    ForEach(logFiles) { file in
                        logFileView(file)
                    }
                }
            }
        }
    }

    private func logFileView(_ file: LaunchdLogFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(file.roleTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button("显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(!file.exists)
            }

            Text(logMeta(file))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let failure = file.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if !file.exists {
                Text("文件还不存在 —— 任务可能一次都没运行过。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if file.tail.isEmpty {
                Text("文件是空的。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                logTailView(file)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Pinned to the bottom: the newest lines are the ones worth seeing first.
    private func logTailView(_ file: LaunchdLogFile) -> some View {
        MonospacedTextView(text: file.tail, scrollsToBottom: true)
            .frame(height: MonospacedTextView.height(for: file.tail, maximum: 240))
            .background(.background.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func logMeta(_ file: LaunchdLogFile) -> String {
        guard file.exists else { return "—" }
        var parts = [Self.byteFormatter.string(fromByteCount: file.byteSize)]
        if let modifiedAt = file.modifiedAt {
            parts.append("更新于 " + Self.fullFormatter.string(from: modifiedAt))
        }
        if file.isTruncated {
            parts.append("仅显示末尾 \(LaunchdLogReader.maxLines) 行以内")
        }
        return parts.joined(separator: " · ")
    }

    private func reloadLogs() {
        guard !job.logPaths.isEmpty else {
            logFiles = []
            return
        }
        isLoadingLogs = true
        let job = job
        Task {
            let files = await Task.detached(priority: .userInitiated) {
                LaunchdLogReader.files(for: job)
            }.value
            guard job.label == self.job.label else { return }
            logFiles = files
            isLoadingLogs = false
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    @ViewBuilder
    private var configurationSection: some View {
        if job.configuration.isEmpty {
            EmptyView()
        } else {
            card("完整配置", systemImage: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(job.configuration) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.value)
                                .font(.system(.callout, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var rawSections: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let plistText {
                DisclosureGroup("plist 原文", isExpanded: $showsRawPlist) {
                    rawText(plistText)
                }
            }
            DisclosureGroup("launchctl print 输出", isExpanded: $showsPrintOutput) {
                if let printOutput {
                    rawText(printOutput)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .font(.callout)
    }

    private func rawText(_ text: String) -> some View {
        MonospacedTextView(text: text, scrollsToBottom: false)
            .frame(height: MonospacedTextView.height(for: text, maximum: 360))
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.top, 6)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
            .clipShape(Capsule())
    }

    private func card<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter
    }()
}

/// Log and raw-output blocks run through AppKit rather than `Text`.
///
/// A few hundred lines in a selectable SwiftUI `Text` re-lay out on every
/// rebuild of the enclosing view — and the detail pane rebuilds on every clock
/// tick — which is what made opening a job with a real log feel stuck.
/// `NSTextView` keeps its own layout across those rebuilds and only does work
/// when the string actually changes.
private struct MonospacedTextView: NSViewRepresentable {
    let text: String
    let scrollsToBottom: Bool

    static func height(for text: String, maximum: CGFloat) -> CGFloat {
        let lines = text.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        return min(max(CGFloat(lines) * 15 + 16, 56), maximum)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 6, height: 6)
            textView.font = .monospacedSystemFont(
                ofSize: NSFont.smallSystemFontSize,
                weight: .regular
            )
            apply(text, to: textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        apply(text, to: textView)
    }

    private func apply(_ text: String, to textView: NSTextView) {
        textView.string = text
        guard scrollsToBottom else { return }
        // The layout is not final until this pass ends, so the newest lines can
        // only be scrolled to afterwards.
        DispatchQueue.main.async {
            textView.scrollToEndOfDocument(nil)
        }
    }
}
