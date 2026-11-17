import AppKit
import SwiftUI

/// Persistent copy-only tool; the shortcut picker keeps its separate paste flow.
@MainActor
final class TimestampWindowController {
    private var panel: TimestampDesktopPanel?
    private let model = TimestampViewModel()

    func restore() {
        if UserDefaults.standard.bool(forKey: "timestampWindowVisible") { show(activate: false) }
    }

    func show(activate: Bool = true) {
        if panel == nil {
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
            window.contentView = NSHostingView(rootView: TimestampWindowView(
                model: model, close: { [weak self] in self?.close() },
                setPinned: { [weak self] in self?.panel?.level = $0 ? .floating : .normal }
            ))
            window.center()
            window.setFrameAutosaveName("TimestampDesktopWindow")
            window.setContentSize(NSSize(width: 500, height: 374))
            if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(window.frame) }) { window.center() }
            window.level = UserDefaults.standard.bool(forKey: "timestampWindowPinned") ? .floating : .normal
            panel = window
        }
        model.start()
        UserDefaults.standard.set(true, forKey: "timestampWindowVisible")
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            panel?.orderFrontRegardless()
        } else {
            panel?.orderFront(nil)
        }
    }

    private func close() {
        UserDefaults.standard.set(false, forKey: "timestampWindowVisible")
        model.stop()
        panel?.orderOut(nil)
    }
}

private final class TimestampDesktopPanel: NSPanel {
    var closeTool: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            closeTool?()
            return
        }
        super.sendEvent(event)
    }
}
