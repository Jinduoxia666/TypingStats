import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        switch state.permissionStatus {
        case .granted:
            Text(Self.compact(CharEstimate.characters(fromKeystrokes: state.todayKeystrokesMerged, factor: state.keystrokesPerCharacter)))
                .monospacedDigit()
        case .denied, .unknown:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    /// Keeps the always-visible menu-bar number short: at most 3 digits, using
    /// k/m/b suffixes above 999 (e.g. 999 → "999", 1200 → "1.2k", 45000 → "45k").
    static func compact(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        var value = Double(n)
        var unit = ""
        for u in ["k", "m", "b"] {
            value /= 1000
            unit = u
            if value < 1000 { break }
        }
        return value < 10
            ? String(format: "%.1f%@", value, unit)
            : String(format: "%.0f%@", value, unit)
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if state.permissionStatus != .granted {
                permissionPrompt
            } else {
                statsRows
            }

            Divider()
            actions
        }
        .padding(16)
        .frame(width: 280)
    }

    private var header: some View {
        HStack {
            Image(systemName: "keyboard")
            Text("今日字数").font(.headline)
            Spacer()
        }
    }

    private var statsRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(estimatedChars)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("字").foregroundStyle(.secondary)
                Spacer()
            }
            Text("本机 \(localChars) 字")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if state.otherDevicesTodayKeystrokes > 0 {
                Text("含其他设备 \(otherDevicesChars) 字")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                Image(systemName: hardwareIconName)
                    .foregroundStyle(.secondary)
                Text(hardwareLabelText)
                Spacer()
                Text(hardwareValueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.top, 8)

            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .foregroundStyle(.secondary)
                Text("本应用内存")
                Spacer()
                Text(appMemoryText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            HStack(spacing: 6) {
                Image(systemName: "chart.pie")
                    .foregroundStyle(.secondary)
                Text("系统内存")
                Spacer()
                Text(systemMemoryText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var estimatedChars: Int {
        CharEstimate.characters(fromKeystrokes: state.todayKeystrokesMerged, factor: state.keystrokesPerCharacter)
    }

    private var localChars: Int {
        CharEstimate.characters(fromKeystrokes: state.todayKeystrokes, factor: state.keystrokesPerCharacter)
    }

    private var otherDevicesChars: Int {
        CharEstimate.characters(fromKeystrokes: state.otherDevicesTodayKeystrokes, factor: state.keystrokesPerCharacter)
    }

    private var hardwareIconName: String {
        state.cpuTemperatureCelsius == nil ? "thermometer.sun" : "thermometer.medium"
    }

    private var hardwareLabelText: String {
        state.cpuTemperatureCelsius == nil ? "系统热状态" : "CPU 温度"
    }

    private var hardwareValueText: String {
        if let value = state.cpuTemperatureCelsius {
            return "\(Int(value.rounded()))°C"
        }

        switch state.systemThermalState {
        case .nominal:
            return "正常"
        case .fair:
            return "轻微"
        case .serious:
            return "严重"
        case .critical:
            return "危险"
        @unknown default:
            return "未知"
        }
    }

    private var appMemoryText: String {
        guard let memoryStats = state.memoryStats else { return "不可用" }
        return formatBytes(memoryStats.appResidentBytes)
    }

    private var systemMemoryText: String {
        guard let memoryStats = state.memoryStats else { return "不可用" }
        return "\(formatBytes(memoryStats.systemUsedBytes)) / \(formatBytes(memoryStats.systemTotalBytes))"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        let gb = value / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        return "\(Int((value / 1_048_576).rounded())) MB"
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("需要辅助功能权限才能开始计数")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("授予权限") {
                state.requestAccessibilityPermission()
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("打开主窗口") { openMainWindow() }
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    /// LSUIElement (menu-bar) apps don't activate or raise windows on their own,
    /// so `openWindow` alone leaves the window behind other apps. Activate the
    /// app and force the main window to the front on the next run-loop tick
    /// (after `openWindow` has created/registered it).
    private func openMainWindow() {
        state.closeClipboardHistory()
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        DispatchQueue.main.async {
            state.closeClipboardHistory()
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }
}
