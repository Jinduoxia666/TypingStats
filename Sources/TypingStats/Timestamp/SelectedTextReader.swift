import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
enum SelectedTextReader {
    nonisolated static let syntheticEventUserData: Int64 = 0x5453_5043

    private struct PasteboardSnapshotItem {
        let entries: [(NSPasteboard.PasteboardType, Data)]
    }

    static func readSelectedTextSynchronously(from targetApp: NSRunningApplication?) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        if let focused = copyFocusedElement(from: systemWide),
           let selected = selectedText(from: focused) {
            return selected
        }

        if let pid = targetApp?.processIdentifier,
           pid != NSRunningApplication.current.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            if let focused = copyFocusedElement(from: appElement),
               let selected = selectedText(from: focused) {
                return selected
            }
        }

        return nil
    }

    static func readSelectedText(
        from targetApp: NSRunningApplication?,
        clipboardHistory: ClipboardHistoryStore,
        allowCopyFallback: Bool = true
    ) async -> String? {
        if let selected = readSelectedTextSynchronously(from: targetApp) {
            return selected
        }

        guard allowCopyFallback,
              AXIsProcessTrusted(),
              let targetApp,
              !targetApp.isTerminated,
              targetApp.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return nil
        }

        clipboardHistory.beginSuppressingCapture()
        defer { clipboardHistory.endSuppressingCapture() }

        let pasteboard = NSPasteboard.general
        let snapshot = capturePasteboard(pasteboard)
        let initialChangeCount = pasteboard.changeCount

        await waitForConflictingModifierRelease()
        sendCommandC()

        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 15_000_000)
            if pasteboard.changeCount != initialChangeCount {
                let copied = pasteboard.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                restorePasteboard(snapshot, to: pasteboard)
                return (copied?.isEmpty == false) ? copied : nil
            }
        }

        return nil
    }

    private static func copyFocusedElement(from root: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard error == .success, let focusedRef else { return nil }
        return unsafeBitCast(focusedRef, to: AXUIElement.self)
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
           let text = selectedRef as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef {
            var rangedTextRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeRef,
                &rangedTextRef
            ) == .success,
               let text = rangedTextRef as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        var markerRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeRef) == .success,
           let markerRangeRef {
            var markerTextRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                "AXStringForTextMarkerRange" as CFString,
                markerRangeRef,
                &markerTextRef
            ) == .success,
               let text = markerTextRef as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        return nil
    }

    private static func waitForConflictingModifierRelease() async {
        let conflictingFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]
        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline {
            let current = CGEventSource.flagsState(.hidSystemState)
            if current.intersection(conflictingFlags).isEmpty {
                return
            }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }

    private static func sendCommandC() {
        let source = CGEventSource(stateID: .privateState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticEventUserData)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticEventUserData)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func capturePasteboard(_ pasteboard: NSPasteboard) -> [PasteboardSnapshotItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            let entries: [(NSPasteboard.PasteboardType, Data)] = item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return entries.isEmpty ? nil : PasteboardSnapshotItem(entries: entries)
        }
    }

    private static func restorePasteboard(_ snapshot: [PasteboardSnapshotItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot.entries {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
