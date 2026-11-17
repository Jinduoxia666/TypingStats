import AppKit
import SwiftUI

@MainActor
final class CalculatorWindowController {
    private var panel: CalculatorPanel?
    private let model = CalculatorModel()

    init() {
        if UserDefaults.standard.bool(forKey: "calculatorScientific") { model.press("SCI") }
        if UserDefaults.standard.bool(forKey: "calculatorRadians") { model.press("DEG") }
    }

    func restore() {
        if UserDefaults.standard.bool(forKey: "calculatorVisible") { show(activate: false) }
    }

    func show(activate: Bool = true) {
        if panel == nil {
            let window = CalculatorPanel(contentRect: NSRect(x: 0, y: 0, width: model.scientific ? 466 : 292, height: 420),
                                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "桌面计算器"
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.model = model
            window.closeCalculator = { [weak self] in self?.close() }
            window.contentView = NSHostingView(rootView: CalculatorView(
                model: model, close: { [weak self] in self?.close() },
                setPinned: { [weak self] in self?.panel?.level = $0 ? .floating : .normal },
                resize: { [weak self] in self?.resize(scientific: $0) }
            ))
            window.center()
            window.setFrameAutosaveName("DesktopCalculator")
            window.setContentSize(NSSize(width: model.scientific ? 466 : 292, height: 420))
            // Keep a restored window reachable after disconnecting a display.
            if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(window.frame) }) {
                window.center()
            }
            window.level = UserDefaults.standard.bool(forKey: "calculatorPinned") ? .floating : .normal
            panel = window
        }
        UserDefaults.standard.set(true, forKey: "calculatorVisible")
        if activate {
            // A nonactivating panel in a menu-bar app can otherwise remain
            // behind the active app's windows at the normal window level.
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            panel?.orderFrontRegardless()
        } else {
            panel?.orderFront(nil)
        }
    }

    private func resize(scientific: Bool) {
        guard let panel else { return }
        var frame = panel.frame
        frame.size = NSSize(width: scientific ? 466 : 292, height: 420)
        if let screen = panel.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        panel.setFrame(frame, display: true)
    }

    private func close() {
        UserDefaults.standard.set(false, forKey: "calculatorVisible")
        panel?.orderOut(nil)
    }
}

private final class CalculatorPanel: NSPanel {
    var model: CalculatorModel?
    var closeCalculator: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let command = event.modifierFlags.contains(.command)
            if command, event.charactersIgnoringModifiers == "w" { closeCalculator?(); return }
            if command, event.charactersIgnoringModifiers == "c" {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model?.display ?? "0", forType: .string)
                return
            }
            if !command && !event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.option) {
                let character = event.characters ?? ""
                let key: String
                switch event.keyCode {
                case 36, 76: key = "="
                case 51, 117: key = "⌫"
                case 53: key = "C"
                default:
                    key = ["-": "−", "*": "×", "/": "÷", ",": ".", "c": "C"][character] ?? character
                }
                if ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "+", "−", "×", "÷", "%", "=", "C", "⌫", "(", ")", "^"].contains(key) {
                    model?.press(key)
                    return
                }
            }
        }
        super.sendEvent(event)
    }
}
