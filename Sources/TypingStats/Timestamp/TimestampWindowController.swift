import AppKit
import SwiftUI

enum TimestampPanelKeyAction: Equatable {
    case close
    case moveSelection(Int)
    case confirmSelection
}

@MainActor
final class TimestampWindowController {
    var onPasteBack: ((NSRunningApplication) -> Void)?

    private var panel: TimestampDesktopPanel?
    private let model = TimestampViewModel()
    private var pasteTargetApplication: NSRunningApplication?
    private var presentationToken = UUID()

    private var isPinned: Bool {
        UserDefaults.standard.bool(forKey: "timestampWindowPinned")
    }

    func restore() {
        if UserDefaults.standard.bool(forKey: "timestampWindowVisible") {
            showFromMenuBar(input: nil, activate: false)
        }
    }

    func showFromMenuBar(input: String? = nil, activate: Bool = true) {
        let wasVisible = panel?.isVisible == true
        ensurePanel()
        applyPinnedLevel()
        pasteTargetApplication = nil
        model.canPasteBack = false
        if !wasVisible {
            model.copiedValue = nil
            if let input, !input.isEmpty {
                model.input = input
                model.select(at: 0)
            }
        }
        model.start()
        UserDefaults.standard.set(true, forKey: "timestampWindowVisible")
        if activate {
            model.requestFocus()
        }
        present(activate: activate)
    }

    func showFromHotKey(input: String?, pasteTarget: NSRunningApplication?) {
        let wasVisible = panel?.isVisible == true
        ensurePanel()
        applyPinnedLevel()
        pasteTargetApplication = pasteTarget
        model.canPasteBack = pasteTarget != nil
        model.copiedValue = nil
        if let input, !input.isEmpty {
            model.input = input
            model.select(at: 0)
        }
        if !wasVisible, let panel {
            let mouse = NSEvent.mouseLocation
            let visibleFrame = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.visibleFrame
                ?? NSScreen.main?.visibleFrame
            if let visibleFrame {
                let origin = Self.frameOriginNearCursor(
                    mouseLocation: mouse,
                    windowSize: panel.frame.size,
                    in: visibleFrame
                )
                panel.setFrameOrigin(origin)
            }
        }
        model.start()
        UserDefaults.standard.set(true, forKey: "timestampWindowVisible")
        model.requestFocus()
        present(activate: true)
    }

    func closeIfUnpinned() {
        guard !isPinned else { return }
        close()
    }

    nonisolated static func frameOriginNearCursor(
        mouseLocation: NSPoint,
        windowSize: NSSize,
        in visibleFrame: NSRect,
        margin: CGFloat = 12
    ) -> NSPoint {
        let preferredX = mouseLocation.x + margin
        let preferredY = mouseLocation.y - windowSize.height - margin
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width - margin)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height - margin)
        return NSPoint(
            x: min(max(preferredX, visibleFrame.minX + margin), maxX),
            y: min(max(preferredY, visibleFrame.minY + margin), maxY)
        )
    }

    nonisolated static func keyAction(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?,
        hasMarkedText: Bool
    ) -> TimestampPanelKeyAction? {
        if modifierFlags.contains(.command), charactersIgnoringModifiers == "w" {
            return .close
        }
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasOtherModifiers = !flags.intersection([.command, .control, .option]).isEmpty
        guard !hasOtherModifiers, !hasMarkedText else { return nil }
        switch keyCode {
        case 53:
            return .close
        case 125:
            return .moveSelection(1)
        case 126:
            return .moveSelection(-1)
        case 36, 76:
            return .confirmSelection
        default:
            return nil
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let window = TimestampDesktopPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 374),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.title = "时间戳转换"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.closeTool = { [weak self] in self?.close() }
        window.onMoveSelection = { [weak self] delta in self?.model.moveSelection(by: delta) }
        window.onConfirmSelection = { [weak self] in self?.confirmSelection() }
        window.contentView = NSHostingView(rootView: TimestampWindowView(
            model: model,
            close: { [weak self] in self?.close() },
            setPinned: { [weak self] pinned in self?.setPinned(pinned) },
            onSelectItem: { [weak self] item in self?.handleItemSelection(item) }
        ))
        window.center()
        window.setFrameAutosaveName("TimestampDesktopWindow")
        window.setContentSize(NSSize(width: 500, height: 374))
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(window.frame) }) { window.center() }
        panel = window
    }

    private func setPinned(_ pinned: Bool) {
        panel?.level = pinned ? .floating : .normal
        if pinned {
            pasteTargetApplication = nil
            model.canPasteBack = false
        }
    }

    private func applyPinnedLevel() {
        panel?.level = isPinned ? .floating : .normal
    }

    private func present(activate: Bool) {
        if activate {
            let token = UUID()
            presentationToken = token
            NSApp.activate(ignoringOtherApps: true)
            for delay in [0.0, 0.05, 0.15] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, token == self.presentationToken, let panel = self.panel else { return }
                    panel.orderFrontRegardless()
                    panel.makeKey()
                    panel.makeKeyAndOrderFront(nil)
                }
            }
        } else {
            presentationToken = UUID()
            panel?.orderFront(nil)
        }
    }

    private func confirmSelection() {
        let items = model.items
        guard items.indices.contains(model.selectionIndex) else { return }
        handleItemSelection(items[model.selectionIndex])
    }

    private func handleItemSelection(_ item: TimestampConversionItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.value, forType: .string)
        if !isPinned, let target = pasteTargetApplication {
            close()
            onPasteBack?(target)
        } else {
            model.copiedValue = item.value
        }
    }

    private func close() {
        presentationToken = UUID()
        UserDefaults.standard.set(false, forKey: "timestampWindowVisible")
        pasteTargetApplication = nil
        model.canPasteBack = false
        model.stop()
        panel?.orderOut(nil)
    }
}

private final class TimestampDesktopPanel: NSPanel {
    var closeTool: (() -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var onConfirmSelection: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        closeTool?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let hasMarkedText = (firstResponder as? NSTextInputClient)?.hasMarkedText() == true
            if let action = TimestampWindowController.keyAction(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                hasMarkedText: hasMarkedText
            ) {
                switch action {
                case .close:
                    closeTool?()
                case .moveSelection(let delta):
                    onMoveSelection?(delta)
                case .confirmSelection:
                    onConfirmSelection?()
                }
                return
            }
        }
        super.sendEvent(event)
    }
}
