import Carbon
import Foundation

final class ClipboardHotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(shortcut: ClipboardShortcut, action: @escaping @MainActor () -> Void) {
        self.action = action
        installHandler()
        update(shortcut: shortcut)
    }

    deinit {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func update(shortcut: ClipboardShortcut) {
        unregister()
        guard shortcut.isUsable else { return }

        let hotKeyID = EventHotKeyID(
            signature: OSType(UInt32(ascii: "TPSC")),
            id: 1
        )
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func installHandler() {
        guard eventHandlerRef == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let monitor = Unmanaged<ClipboardHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in monitor.action() }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }
}

private extension UInt32 {
    init(ascii string: String) {
        self = string.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }
}
