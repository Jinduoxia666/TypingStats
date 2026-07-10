import Foundation
import Combine
import os.log
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var todayKeystrokes: Int = 0 {
        didSet { refreshMenuBarLabel() }
    }
    @Published private(set) var permissionStatus: PermissionStatus = .unknown {
        didSet { refreshMenuBarLabel() }
    }
    @Published private(set) var excludedBundleIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(excludedBundleIds), forKey: Keys.excluded) }
    }
    /// Average keystrokes per character; `字数 = keystrokes / this`.
    @Published var keystrokesPerCharacter: Double {
        didSet {
            UserDefaults.standard.set(keystrokesPerCharacter, forKey: CharEstimate.factorKey)
            refreshMenuBarLabel()
        }
    }
    /// Today's keystrokes contributed by the user's OTHER Macs (via iCloud sync).
    @Published private(set) var otherDevicesTodayKeystrokes: Int = 0 {
        didSet { refreshMenuBarLabel() }
    }
    @Published private(set) var syncAvailable: Bool = false
    @Published private(set) var syncedDevices: [SyncedDeviceInfo] = []
    @Published private(set) var cpuTemperatureCelsius: Double?
    @Published private(set) var systemThermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var memoryStats: MemoryStats?
    @Published private(set) var clipboardItems: [ClipboardHistoryItem] = []
    @Published private(set) var clipboardSelectionIndex: Int = 0
    @Published var timestampInput: String = ""
    @Published private(set) var timestampSelectionIndex: Int = 0
    @Published private(set) var timestampNow = Date()
    @Published var clipboardShortcut: ClipboardShortcut {
        didSet {
            UserDefaults.standard.set(Int(clipboardShortcut.keyCode), forKey: Keys.clipboardShortcutKeyCode)
            UserDefaults.standard.set(Int(clipboardShortcut.modifiers), forKey: Keys.clipboardShortcutModifiers)
            clipboardHotKeyMonitor?.update(shortcut: clipboardShortcut)
        }
    }
    @Published var timestampShortcut: ClipboardShortcut {
        didSet {
            UserDefaults.standard.set(Int(timestampShortcut.keyCode), forKey: Keys.timestampShortcutKeyCode)
            UserDefaults.standard.set(Int(timestampShortcut.modifiers), forKey: Keys.timestampShortcutModifiers)
            timestampHotKeyMonitor?.update(shortcut: timestampShortcut)
        }
    }

    /// Today's total across all of the user's devices.
    var todayKeystrokesMerged: Int { todayKeystrokes + otherDevicesTodayKeystrokes }
    var timestampItems: [TimestampConversionItem] {
        TimestampConversionItem.items(input: timestampInput, now: timestampNow)
    }

    private enum Keys {
        static let excluded = "excludedBundleIds"
        static let clipboardShortcutKeyCode = "clipboardShortcutKeyCode"
        static let clipboardShortcutModifiers = "clipboardShortcutModifiers"
        static let timestampShortcutKeyCode = "timestampShortcutKeyCode"
        static let timestampShortcutModifiers = "timestampShortcutModifiers"
    }

    /// Drives the always-visible menu-bar label; see MenuBarLabelModel for why
    /// it's separate from this (chatty) object.
    let menuBarLabel = MenuBarLabelModel()

    private let monitor: KeystrokeMonitor
    private let database: DatabaseManager
    private let permissions: PermissionsManager
    private let stats = StatsService()
    private let recorder = KeystrokeRecorder()
    private let cloud = CloudSyncStore()
    private let cpuTemperatureReader = CPUTemperatureReader()
    private let memoryStatsReader = MemoryStatsReader()
    private let clipboardHistory = ClipboardHistoryStore()
    private var currentDateKey = StatsService.dateKey(for: Date())
    private var nextRolloverDate = AppState.nextMidnight(after: Date())
    private var exactTodayKeystrokes = 0
    private var countPublishTask: Task<Void, Never>?
    private var permissionTimer: Timer?
    private var syncTimer: Timer?
    private var writeTimer: Timer?
    private var cpuTemperatureTimer: Timer?
    private var timestampTimer: Timer?
    private var clipboardCancellable: AnyCancellable?
    private var clipboardHotKeyMonitor: ClipboardHotKeyMonitor?
    private var clipboardWindowController: ClipboardHistoryWindowController?
    private var clipboardTargetApplication: NSRunningApplication?
    private var timestampHotKeyMonitor: ClipboardHotKeyMonitor?
    private var timestampWindowController: TimestampToolWindowController?
    private var timestampTargetApplication: NSRunningApplication?
    private var lastPasteTargetApplication: NSRunningApplication?
    private var suppressToolWindowsUntil: Date?
    private var isRecordingShortcut = false
    private let syncQueue = DispatchQueue(label: "com.jinduoxia.TypingStats.sync", qos: .utility)
    private let hardwareQueue = DispatchQueue(label: "com.jinduoxia.TypingStats.hardware", qos: .utility)
    private var isRunning = false

    static let logger = Logger(subsystem: "com.jinduoxia.TypingStats", category: "monitor")

    init() {
        let defaults = UserDefaults.standard
        self.excludedBundleIds = Set(defaults.stringArray(forKey: Keys.excluded) ?? [])
        let savedFactor = defaults.double(forKey: CharEstimate.factorKey)
        self.keystrokesPerCharacter = savedFactor > 0 ? savedFactor : CharEstimate.defaultFactor
        let savedKeyCode = defaults.integer(forKey: Keys.clipboardShortcutKeyCode)
        let savedModifiers = defaults.integer(forKey: Keys.clipboardShortcutModifiers)
        self.clipboardShortcut = savedKeyCode > 0 && savedModifiers > 0
            ? ClipboardShortcut(keyCode: UInt32(savedKeyCode), modifiers: UInt32(savedModifiers))
            : .defaultValue
        let savedTimestampKeyCode = defaults.integer(forKey: Keys.timestampShortcutKeyCode)
        let savedTimestampModifiers = defaults.integer(forKey: Keys.timestampShortcutModifiers)
        self.timestampShortcut = savedTimestampKeyCode > 0 && savedTimestampModifiers > 0
            ? ClipboardShortcut(keyCode: UInt32(savedTimestampKeyCode), modifiers: UInt32(savedTimestampModifiers))
            : .timestampDefaultValue

        self.permissions = PermissionsManager()
        self.database = DatabaseManager.shared
        self.monitor = KeystrokeMonitor()

        monitor.onKeystroke = { [weak self] app in
            // The CGEventTap callback runs on the main run loop, so we're already
            // on the main actor's thread — no need to hop through a Task.
            MainActor.assumeIsolated {
                self?.handleKeystroke(app)
            }
        }

        // Restore today's persisted total so the menu bar survives restarts.
        let restoredTodayKeystrokes = (try? stats.todayStats())?.keystrokes ?? 0
        exactTodayKeystrokes = restoredTodayKeystrokes
        todayKeystrokes = restoredTodayKeystrokes
        // Property observers don't fire during init; seed the label explicitly.
        refreshMenuBarLabel()

        refreshPermissions()
        startPermissionWatcher()
        startSync()
        startHardwareMonitoring()
        startClipboardHistory()
        startTimestampTool()
    }

    func start() {
        guard permissionStatus == .granted, !isRunning else { return }
        monitor.start()
        isRunning = true
        Self.logger.notice("Monitor started")
    }

    func stop() {
        monitor.stop()
        clipboardHistory.stop()
        countPublishTask?.cancel()
        countPublishTask = nil
        publishExactTodayKeystrokes()
        recorder.flushNow()
        let cloud = self.cloud
        syncQueue.async { cloud.writeOwnSnapshot() }
        isRunning = false
    }

    func showClipboardHistory() {
        guard canOpenToolWindow else { return }
        closeTimestampTool()
        clipboardTargetApplication = currentPasteTargetApplication()
        selectClipboardItem(at: 0)
        if clipboardWindowController == nil {
            clipboardWindowController = ClipboardHistoryWindowController(state: self)
        }
        clipboardWindowController?.show()
    }

    func closeClipboardHistory(returnToMenuBarOnly: Bool = true) {
        clipboardWindowController?.close(returnToMenuBarOnly: returnToMenuBarOnly)
        clipboardTargetApplication = nil
    }

    func showTimestampTool() {
        guard canOpenToolWindow else { return }
        closeClipboardHistory()
        timestampTargetApplication = currentPasteTargetApplication()
        fillTimestampInputFromPasteboardIfPossible()
        startTimestampTimer()
        selectTimestampItem(at: 0)
        if timestampWindowController == nil {
            timestampWindowController = TimestampToolWindowController(state: self)
        }
        timestampWindowController?.show()
    }

    private func fillTimestampInputFromPasteboardIfPossible() {
        guard let value = NSPasteboard.general.string(forType: .string),
              TimestampConversionItem.isConvertibleInput(value) else {
            return
        }
        timestampInput = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func closeTimestampTool(returnToMenuBarOnly: Bool = true) {
        timestampWindowController?.close(returnToMenuBarOnly: returnToMenuBarOnly)
        timestampTargetApplication = nil
        stopTimestampTimer()
    }

    func prepareToOpenMainWindow() {
        suppressToolWindowsUntil = Date().addingTimeInterval(0.6)
        closeClipboardHistory(returnToMenuBarOnly: false)
        closeTimestampTool(returnToMenuBarOnly: false)
    }

    func setShortcutRecording(_ recording: Bool) {
        isRecordingShortcut = recording
        if recording {
            suppressToolWindowsUntil = .distantFuture
            closeClipboardHistory(returnToMenuBarOnly: false)
            closeTimestampTool(returnToMenuBarOnly: false)
        } else {
            suppressToolWindowsUntil = Date().addingTimeInterval(0.25)
        }
    }

    private var canOpenToolWindow: Bool {
        !isRecordingShortcut && !isSuppressingToolWindows
    }

    private var isSuppressingToolWindows: Bool {
        guard let suppressToolWindowsUntil else { return false }
        if Date() < suppressToolWindowsUntil { return true }
        self.suppressToolWindowsUntil = nil
        return false
    }

    func selectTimestampItem(at index: Int) {
        let items = timestampItems
        guard !items.isEmpty else {
            timestampSelectionIndex = 0
            return
        }
        timestampSelectionIndex = min(max(index, 0), items.count - 1)
    }

    func moveTimestampSelection(by delta: Int) {
        selectTimestampItem(at: timestampSelectionIndex + delta)
    }

    func pasteSelectedTimestampItem() {
        let items = timestampItems
        guard items.indices.contains(timestampSelectionIndex) else { return }
        pasteTimestampItem(items[timestampSelectionIndex])
    }

    func pasteTimestampItem(_ item: TimestampConversionItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.value, forType: .string)
        timestampWindowController?.close()

        pasteIntoTarget(timestampTargetApplication)
    }

    private func startTimestampTimer() {
        timestampTimer?.invalidate()
        timestampNow = Date()
        timestampTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.timestampNow = Date() }
        }
    }

    private func stopTimestampTimer() {
        timestampTimer?.invalidate()
        timestampTimer = nil
    }

    func pasteClipboardItem(_ item: ClipboardHistoryItem) {
        clipboardHistory.writeToPasteboard(item)
        clipboardWindowController?.close()

        pasteIntoTarget(clipboardTargetApplication)
    }

    private func currentPasteTargetApplication() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return lastPasteTargetApplication
        }
        if app.processIdentifier == NSRunningApplication.current.processIdentifier {
            return lastPasteTargetApplication
        }
        lastPasteTargetApplication = app
        return app
    }

    private func pasteIntoTarget(_ target: NSRunningApplication?) {
        guard let target, !target.isTerminated else { return }
        AppActivation.returnToMenuBarOnly()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            target.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                Self.sendCommandV()
            }
        }
    }

    func clearClipboardHistory() {
        clipboardHistory.clear()
    }

    func selectClipboardItem(at index: Int) {
        guard !clipboardItems.isEmpty else {
            clipboardSelectionIndex = 0
            return
        }
        let maxIndex = min(clipboardItems.count, ClipboardPickerConfig.maxItems) - 1
        clipboardSelectionIndex = min(max(index, 0), maxIndex)
    }

    func moveClipboardSelection(by delta: Int) {
        selectClipboardItem(at: clipboardSelectionIndex + delta)
    }

    func pasteSelectedClipboardItem() {
        guard clipboardItems.indices.contains(clipboardSelectionIndex) else { return }
        pasteClipboardItem(clipboardItems[clipboardSelectionIndex])
    }

    // MARK: - iCloud sync
    //
    // Each device writes its own snapshot to the shared iCloud Drive folder and
    // reads the others', summing them for a cross-device view. See CloudSyncStore.

    private func startSync() {
        syncAvailable = cloud.isAvailable
        guard cloud.isAvailable else {
            Self.logger.notice("iCloud sync unavailable (iCloud Drive off?)")
            return
        }
        cloud.ensureFolder()
        refreshSync()
        // Read the other devices often so the merged view stays fresh, but only
        // write our own snapshot to iCloud every 5 minutes to limit churn.
        syncTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pullOthers() }
        }
        writeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pushSnapshot() }
        }
    }

    /// Manual "sync now": push our snapshot, pull the others, and republish the
    /// merged today total + device list.
    func syncNow() { refreshSync() }

    private func refreshSync() {
        pushSnapshot()
        pullOthers()
    }

    /// Write this device's snapshot to iCloud (on the serial sync queue).
    private func pushSnapshot() {
        guard cloud.isAvailable else { return }
        let cloud = self.cloud
        syncQueue.async { cloud.writeOwnSnapshot() }
    }

    /// Read every other device's snapshot and republish the merged today total
    /// and the device list.
    private func pullOthers() {
        guard cloud.isAvailable else { return }
        let cloud = self.cloud
        syncQueue.async { [weak self] in
            let others = cloud.otherSnapshots()
            let key = StatsService.dateKey(for: Date())
            let othersToday = others.reduce(0) { $0 + ($1.days[key]?.keystrokes ?? 0) }
            let otherInfos = others.map { snap in
                SyncedDeviceInfo(
                    id: snap.deviceId,
                    name: snap.deviceName,
                    updatedAt: Date(timeIntervalSince1970: snap.updatedAt),
                    todayKeystrokes: snap.days[key]?.keystrokes ?? 0,
                    isSelf: false
                )
            }
            Task { @MainActor in
                guard let self else { return }
                self.otherDevicesTodayKeystrokes = othersToday
                let selfInfo = SyncedDeviceInfo(
                    id: DeviceIdentity.id,
                    name: DeviceIdentity.name,
                    updatedAt: Date(),
                    todayKeystrokes: self.todayKeystrokes,
                    isSelf: true
                )
                self.syncedDevices = [selfInfo] + otherInfos.sorted { $0.name < $1.name }
            }
        }
    }

    private func refreshMenuBarLabel() {
        let chars = CharEstimate.characters(fromKeystrokes: todayKeystrokesMerged, factor: keystrokesPerCharacter)
        menuBarLabel.update(
            text: MenuBarLabelModel.compact(chars),
            showsWarning: permissionStatus != .granted
        )
    }

    func refreshPermissions() {
        let new = permissions.currentStatus()
        guard new != permissionStatus else { return }
        permissionStatus = new
        Self.logger.notice("Accessibility permission status -> \(String(describing: new), privacy: .public)")
        if new == .granted { start() }
    }

    func requestAccessibilityPermission() {
        permissions.promptForAccessibility()
    }

    private func startPermissionWatcher() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    private func startHardwareMonitoring() {
        refreshHardwareStats()
        cpuTemperatureTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshHardwareStats() }
        }
    }

    private func startClipboardHistory() {
        clipboardItems = clipboardHistory.items
        clipboardCancellable = clipboardHistory.$items.sink { [weak self] items in
            self?.clipboardItems = items
            self?.selectClipboardItem(at: self?.clipboardSelectionIndex ?? 0)
        }
        clipboardHistory.start()

        let monitor = ClipboardHotKeyMonitor(shortcut: clipboardShortcut) { [weak self] in
            self?.showClipboardHistory()
        }
        clipboardHotKeyMonitor = monitor
    }

    private func startTimestampTool() {
        let monitor = ClipboardHotKeyMonitor(
            shortcut: timestampShortcut,
            signature: "TPST",
            id: 2
        ) { [weak self] in
            self?.showTimestampTool()
        }
        timestampHotKeyMonitor = monitor
    }

    private func refreshHardwareStats() {
        let temperatureReader = cpuTemperatureReader
        let memoryReader = memoryStatsReader
        hardwareQueue.async { [weak self] in
            let value = temperatureReader.readCelsius()
            let thermalState = ProcessInfo.processInfo.thermalState
            let memoryStats = memoryReader.read()
            Task { @MainActor in
                self?.cpuTemperatureCelsius = value
                self?.systemThermalState = thermalState
                self?.memoryStats = memoryStats
            }
        }
    }

    func setExcluded(_ bundleId: String, excluded: Bool) {
        if excluded { excludedBundleIds.insert(bundleId) }
        else { excludedBundleIds.remove(bundleId) }
    }

    private func handleKeystroke(_ frontApp: FrontmostApp?) {
        rolloverIfNeeded()
        if let id = frontApp?.bundleId, excludedBundleIds.contains(id) { return }
        exactTodayKeystrokes += 1
        scheduleCountPublication()
        recorder.record(app: frontApp)
    }

    private func scheduleCountPublication() {
        guard countPublishTask == nil else { return }
        countPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.publishExactTodayKeystrokes()
        }
    }

    private func publishExactTodayKeystrokes() {
        countPublishTask = nil
        guard todayKeystrokes != exactTodayKeystrokes else { return }
        todayKeystrokes = exactTodayKeystrokes
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// When the local day flips while the app is running, reset the in-memory
    /// "today" total (reloaded from the DB, which is ~empty for the new day).
    /// Compares against a cached midnight so the per-keystroke check is a plain
    /// Date comparison, not a date-format round trip.
    private func rolloverIfNeeded() {
        guard Date() >= nextRolloverDate else { return }
        nextRolloverDate = Self.nextMidnight(after: Date())
        currentDateKey = StatsService.dateKey(for: Date())
        countPublishTask?.cancel()
        countPublishTask = nil
        exactTodayKeystrokes = (try? stats.todayStats())?.keystrokes ?? 0
        todayKeystrokes = exactTodayKeystrokes
    }

    private static func nextMidnight(after date: Date) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        return cal.startOfDay(for: tomorrow)
    }
}
