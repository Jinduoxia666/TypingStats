import Foundation
import AppKit
import CoreGraphics
import os.log

struct FrontmostApp: Equatable {
    let bundleId: String
    let name: String
}

private let monitorLogger = Logger(subsystem: "com.jinduoxia.TypingStats", category: "monitor")

/// Counts keystrokes globally via a CGEventTap. Unlike the old AX text-reading
/// approach, this works in every app — including self-drawn ones (WeChat,
/// terminals, Figma) — because it observes raw keyboard events, not text content.
///
/// Only `keyDown` events are observed, so modifier-only presses (Shift/Cmd/…),
/// which arrive as `flagsChanged`, are naturally excluded. Auto-repeat (holding
/// a key) is filtered out, so one physical press counts once.
///
/// Requires Accessibility permission (same TCC grant the app already uses); no
/// separate "Input Monitoring" permission is needed when Accessibility is held.
final class KeystrokeMonitor {
    /// Called on the main thread once per counted keystroke, with the frontmost app.
    var onKeystroke: ((FrontmostApp?) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?
    private var currentApp: FrontmostApp?

    func start() {
        observeFrontmostApp()
        updateCurrentApp(NSWorkspace.shared.frontmostApplication)
        installTap()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
        if let token = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            workspaceObserver = nil
        }
    }

    private func installTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keystrokeTapCallback,
            userInfo: refcon
        ) else {
            monitorLogger.error("CGEventTap creation failed — is Accessibility permission granted?")
            return
        }
        self.tap = tap

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        monitorLogger.notice("keystroke tap installed")
    }

    /// The system disables a tap if its callback is too slow or on some user
    /// input; re-enable it so counting resumes.
    fileprivate func reEnableTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        monitorLogger.notice("keystroke tap re-enabled")
    }

    fileprivate func handleKeyDown(_ event: CGEvent) {
        // Ignore auto-repeat so holding a key counts as a single press.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
        // Only the 26 letters and digits 0–9 count toward the character estimate;
        // punctuation, space, return, navigation and delete keys don't. Each such
        // latin keystroke is one English char or one pinyin stroke.
        guard producesAlphanumeric(event) else { return }
        onKeystroke?(currentApp)
    }

    /// True when this key event produces a single ASCII letter or digit. Uses the
    /// layout-translated character; for pinyin input the tap sees the event before
    /// the IME, so it's still the latin letter of the physical key.
    private func producesAlphanumeric(_ event: CGEvent) -> Bool {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length == 1, let scalar = UnicodeScalar(chars[0]) else { return false }
        guard scalar.isASCII else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private func observeFrontmostApp() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateCurrentApp(app)
        }
    }

    private func updateCurrentApp(_ app: NSRunningApplication?) {
        guard let app, let bundleId = app.bundleIdentifier else {
            currentApp = nil
            return
        }
        // Don't attribute keystrokes to ourselves.
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            currentApp = nil
            return
        }
        currentApp = FrontmostApp(bundleId: bundleId, name: app.localizedName ?? bundleId)
    }
}

private func keystrokeTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<KeystrokeMonitor>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .keyDown:
        owner.handleKeyDown(event)
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        owner.reEnableTap()
    default:
        break
    }
    // listenOnly tap: pass the event through untouched.
    return Unmanaged.passUnretained(event)
}
