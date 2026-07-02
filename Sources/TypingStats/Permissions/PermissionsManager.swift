import Foundation
import ApplicationServices
import AppKit

enum PermissionStatus: Equatable {
    case unknown
    case granted
    case denied
}

final class PermissionsManager {
    func currentStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Triggers the system prompt and (if user agrees) takes them to System Settings.
    func promptForAccessibility() {
        let options: [String: Any] = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
