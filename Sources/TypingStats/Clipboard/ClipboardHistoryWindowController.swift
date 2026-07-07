import AppKit
import SwiftUI

@MainActor
final class ClipboardHistoryWindowController {
    private weak var state: AppState?
    private var window: KeyablePanel?
    private var keyInterceptor: ToolPanelKeyInterceptor?
    private var presentationToken = UUID()

    init(state: AppState) {
        self.state = state
    }

    func show() {
        guard let state else { return }
        presentationToken = UUID()

        if window == nil {
            let panel = KeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 292),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.level = .popUpMenu
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
        bringPanelToFront()
    }

    func close(returnToMenuBarOnly: Bool = true) {
        presentationToken = UUID()
        removeKeyMonitor()
        window?.orderOut(nil)
        window?.close()
        window = nil
        if returnToMenuBarOnly {
            AppActivation.returnToMenuBarOnly()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        let interceptor = ToolPanelKeyInterceptor(keyCodes: [18, 19, 20, 21, 22, 23, 26, 28, 36, 53, 76, 125, 126]) { [weak self] keyCode in
            self?.handle(keyCode)
        }
        interceptor.start()
        keyInterceptor = interceptor
    }

    private func removeKeyMonitor() {
        keyInterceptor?.stop()
        keyInterceptor = nil
    }

    private func handle(_ keyCode: UInt16) {
        guard let state else { return }
        switch keyCode {
        case 53:
            close()
        case 125:
            state.moveClipboardSelection(by: 1)
        case 126:
            state.moveClipboardSelection(by: -1)
        case 36, 76:
            state.pasteSelectedClipboardItem()
        default:
            let mapping: [UInt16: Int] = [
                18: 0, 19: 1, 20: 2, 21: 3,
                23: 4, 22: 5, 26: 6, 28: 7
            ]
            guard let index = mapping[keyCode],
                  state.clipboardItems.indices.contains(index) else {
                return
            }
            state.selectClipboardItem(at: index)
            state.pasteSelectedClipboardItem()
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

    private func bringPanelToFront() {
        let token = presentationToken
        for delay in [0.0, 0.05, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, token == self.presentationToken, let window = self.window else { return }
                window.orderFrontRegardless()
                window.makeKey()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
