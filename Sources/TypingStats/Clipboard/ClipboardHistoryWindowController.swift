import AppKit
import SwiftUI

@MainActor
final class ClipboardHistoryWindowController {
    private weak var state: AppState?
    private var window: KeyablePanel?
    private var keyMonitor: Any?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        guard let state else { return }

        if window == nil {
            let panel = KeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 292),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(
                rootView: ClipboardQuickPickerView()
                    .environmentObject(state)
            )
            window = panel
        }

        resizeForContent()
        positionNearCursor()
        installKeyMonitor()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        removeKeyMonitor()
        AppActivation.returnToMenuBarOnly()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let state else { return false }
        switch event.keyCode {
        case 53:
            close()
            return true
        case 125:
            state.moveClipboardSelection(by: 1)
            return true
        case 126:
            state.moveClipboardSelection(by: -1)
            return true
        case 36, 76:
            state.pasteSelectedClipboardItem()
            return true
        default:
            let mapping: [UInt16: Int] = [
                18: 0, 19: 1, 20: 2, 21: 3,
                23: 4, 22: 5, 26: 6, 28: 7
            ]
            guard let index = mapping[event.keyCode],
                  state.clipboardItems.indices.contains(index) else {
                return false
            }
            state.selectClipboardItem(at: index)
            state.pasteSelectedClipboardItem()
            return true
        }
    }

    private func resizeForContent() {
        guard let window, let state else { return }
        let visibleCount = min(max(state.clipboardItems.count, 1), ClipboardPickerConfig.maxItems)
        let listHeight = min(CGFloat(visibleCount) * ClipboardPickerConfig.rowHeight, ClipboardPickerConfig.maxListHeight)
        let height = state.clipboardItems.isEmpty ? 160 : listHeight + 16
        window.setContentSize(NSSize(width: 460, height: height))
    }

    private func positionNearCursor() {
        guard let window, let screen = NSScreen.main else { return }
        let frame = window.frame
        let mouse = NSEvent.mouseLocation
        let screenFrame = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.visibleFrame ?? screen.visibleFrame
        let margin: CGFloat = 12
        let preferredX = mouse.x + margin
        let preferredY = mouse.y - frame.height - margin
        let x = min(max(preferredX, screenFrame.minX + margin), screenFrame.maxX - frame.width - margin)
        let y = min(max(preferredY, screenFrame.minY + margin), screenFrame.maxY - frame.height - margin)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
