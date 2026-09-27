import AppKit
import Combine
import SwiftUI

/// Owns a single transparent panel, avoiding MenuBarExtra's additional surface.
@MainActor
final class MenuBarPanelController: NSObject, ObservableObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var panel: MenuPanel?
    private var labelSubscription: AnyCancellable?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private weak var state: AppState?
    private weak var inputSource: FixedInputSourceController?
    private var openWindow: OpenWindowAction?

    func configure(state: AppState, inputSource: FixedInputSourceController, openWindow: OpenWindowAction) {
        self.openWindow = openWindow
        guard statusItem == nil else { return }
        self.state = state
        self.inputSource = inputSource
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        item.button?.toolTip = "TypingStats"
        labelSubscription = state.menuBarLabel.$text
            .combineLatest(state.menuBarLabel.$showsWarning)
            .receive(on: RunLoop.main)
            .sink { [weak self] text, warning in
                guard let button = self?.statusItem?.button else { return }
                button.title = warning ? "" : text
                button.image = warning ? NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "需要辅助功能权限") : nil
                button.setAccessibilityLabel("TypingStats，今日输入 \(text)")
            }
    }

    @objc private func togglePanel() {
        if panel != nil { close(); return }
        guard let state, let inputSource, let openWindow,
              let button = statusItem?.button, let buttonWindow = button.window else { return }

        let root = MenuBarContentView(
            dismissMenu: { [weak self] in self?.close() },
            showMainWindow: { openWindow(id: "main") }
        )
            .environmentObject(state)
            .environmentObject(state.hardwareStats)
            .environmentObject(inputSource)
        let hostingView = NSHostingView(rootView: root)
        let size = hostingView.fittingSize
        let window = MenuPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = hostingView
        window.delegate = self
        window.onCancel = { [weak self] in self?.close() }
        panel = window

        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        window.setFrameOrigin(NSPoint(x: x, y: anchor.minY - size.height - 3))
        button.highlight(true)
        window.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    private func installDismissMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel && event.window !== self.statusItem?.button?.window {
                self.close()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func close() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
        let oldPanel = panel
        panel = nil
        oldPanel?.delegate = nil
        oldPanel?.orderOut(nil)
        oldPanel?.contentView = nil
        oldPanel?.close()
        statusItem?.button?.highlight(false)
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    deinit {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

private final class MenuPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
