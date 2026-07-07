import Carbon
import Foundation

final class ClipboardHotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID: EventHotKeyID
    private let action: @MainActor () -> Void

    init(
        shortcut: ClipboardShortcut,
        signature: String = "TPSC",
        id: UInt32 = 1,
        action: @escaping @MainActor () -> Void
    ) {
        self.hotKeyID = EventHotKeyID(signature: OSType(UInt32(ascii: signature)), id: id)
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
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let monitor = Unmanaged<ClipboardHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                guard monitor.matches(event: event) else { return OSStatus(eventNotHandledErr) }
                Task { @MainActor in monitor.action() }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func matches(event: EventRef) -> Bool {
        var pressedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedID
        )
        return status == noErr
            && pressedID.signature == hotKeyID.signature
            && pressedID.id == hotKeyID.id
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
