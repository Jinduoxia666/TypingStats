import Foundation
import Combine
import os.log
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var todayKeystrokes: Int = 0
    @Published private(set) var permissionStatus: PermissionStatus = .unknown
    @Published private(set) var excludedBundleIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(excludedBundleIds), forKey: Keys.excluded) }
    }
    /// Average keystrokes per character; `字数 = keystrokes / this`.
    @Published var keystrokesPerCharacter: Double {
        didSet { UserDefaults.standard.set(keystrokesPerCharacter, forKey: CharEstimate.factorKey) }
    }
    /// Today's keystrokes contributed by the user's OTHER Macs (via iCloud sync).
    @Published private(set) var otherDevicesTodayKeystrokes: Int = 0
    @Published private(set) var syncAvailable: Bool = false
    @Published private(set) var syncedDevices: [SyncedDeviceInfo] = []
    @Published private(set) var cpuTemperatureCelsius: Double?
    @Published private(set) var systemThermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var memoryStats: MemoryStats?
    @Published private(set) var clipboardItems: [ClipboardHistoryItem] = []
    @Published private(set) var clipboardSelectionIndex: Int = 0
    @Published var clipboardShortcut: ClipboardShortcut {
        didSet {
            UserDefaults.standard.set(Int(clipboardShortcut.keyCode), forKey: Keys.clipboardShortcutKeyCode)
            UserDefaults.standard.set(Int(clipboardShortcut.modifiers), forKey: Keys.clipboardShortcutModifiers)
            clipboardHotKeyMonitor?.update(shortcut: clipboardShortcut)
        }
    }

    /// Today's total across all of the user's devices.
    var todayKeystrokesMerged: Int { todayKeystrokes + otherDevicesTodayKeystrokes }

    private enum Keys {
        static let excluded = "excludedBundleIds"
        static let clipboardShortcutKeyCode = "clipboardShortcutKeyCode"
        static let clipboardShortcutModifiers = "clipboardShortcutModifiers"
    }

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
    private var permissionTimer: Timer?
    private var syncTimer: Timer?
    private var writeTimer: Timer?
    private var cpuTemperatureTimer: Timer?
    private var clipboardCancellable: AnyCancellable?
    private var clipboardHotKeyMonitor: ClipboardHotKeyMonitor?
    private var clipboardWindowController: ClipboardHistoryWindowController?
    private weak var clipboardTargetApplication: NSRunningApplication?
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
        todayKeystrokes = (try? stats.todayStats())?.keystrokes ?? 0

        refreshPermissions()
        startPermissionWatcher()
        startSync()
        startHardwareMonitoring()
        startClipboardHistory()
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
        recorder.flushNow()
        let cloud = self.cloud
        syncQueue.async { cloud.writeOwnSnapshot() }
        isRunning = false
    }

    func showClipboardHistory() {
        clipboardTargetApplication = NSWorkspace.shared.frontmostApplication
        selectClipboardItem(at: 0)
        if clipboardWindowController == nil {
            clipboardWindowController = ClipboardHistoryWindowController(state: self)
        }
        clipboardWindowController?.show()
    }

    func closeClipboardHistory() {
        clipboardWindowController?.close()
        clipboardTargetApplication = nil
    }

    func pasteClipboardItem(_ item: ClipboardHistoryItem) {
        clipboardHistory.writeToPasteboard(item)
        clipboardWindowController?.close()

        let target = clipboardTargetApplication
        AppActivation.returnToMenuBarOnly()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            target?.activate(options: [.activateIgnoringOtherApps])
            Self.sendCommandV()
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
        todayKeystrokes += 1
        recorder.record(app: frontApp)
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
    private func rolloverIfNeeded() {
        let key = StatsService.dateKey(for: Date())
        guard key != currentDateKey else { return }
        currentDateKey = key
        todayKeystrokes = (try? stats.todayStats())?.keystrokes ?? 0
    }
}
