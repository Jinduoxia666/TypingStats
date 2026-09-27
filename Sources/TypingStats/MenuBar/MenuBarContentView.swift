import SwiftUI
import AppKit

/// Tiny dedicated model for the always-visible menu-bar label. The label must
/// NOT observe AppState directly: AppState publishes on every keystroke (plus
/// hardware/sync ticks), and re-rendering the MenuBarExtra label that often
/// costs CPU and slowly grows memory. This model publishes only when the
/// rendered text actually changes.
@MainActor
final class MenuBarLabelModel: ObservableObject {
    @Published private(set) var text: String = "0"
    @Published private(set) var showsWarning: Bool = true

    func update(text: String, showsWarning: Bool) {
        if self.text != text { self.text = text }
        if self.showsWarning != showsWarning { self.showsWarning = showsWarning }
    }

    /// Keeps the always-visible menu-bar number short: at most 3 digits, using
    /// k/m/b suffixes above 999 (e.g. 999 → "999", 1200 → "1.2k", 45000 → "45k").
    nonisolated static func compact(_ n: Int) -> String {
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

struct MenuBarLabel: View {
    @EnvironmentObject private var model: MenuBarLabelModel

    var body: some View {
        if model.showsWarning {
            Image(systemName: "exclamationmark.triangle.fill")
        } else {
            Text(model.text)
                .monospacedDigit()
        }
    }
}

struct MenuBarContentView: View {
    var dismissMenu: () -> Void
    var showMainWindow: () -> Void

    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var hardware: HardwareStatsModel
    @EnvironmentObject private var fixedInputSource: FixedInputSourceController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if state.permissionStatus != .granted {
                permissionPrompt
            } else {
                statsRows
            }

            Divider()
            fixedInputSourceControls

            Divider()
            actions
            Text(versionText)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.2), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack {
            Image(systemName: "keyboard")
            Text("今日字数").font(.headline)
            Spacer()
        }
    }

    private var fixedInputSourceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("固定输入法", systemImage: "keyboard.badge.ellipsis")
                Spacer()
                Toggle("固定输入法", isOn: $fixedInputSource.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            HStack {
                Text("输入法").foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("输入法", selection: $fixedInputSource.selectedInputSourceID) {
                        ForEach(fixedInputSource.availableInputSources) { inputSource in
                            Text(inputSource.name).tag(inputSource.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedInputSourceName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.primary.opacity(0.1))
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(width: 128)
                .accessibilityLabel("输入法")
                .accessibilityValue(selectedInputSourceName)
                .help(selectedInputSourceName)
                .disabled(fixedInputSource.availableInputSources.isEmpty)
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    private var selectedInputSourceName: String {
        fixedInputSource.availableInputSources.first {
            $0.id == fixedInputSource.selectedInputSourceID
        }?.name ?? "暂无可用输入法"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "版本 \(version) · \(build)"
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
            HStack(spacing: 6) {
                Text("本机 \(localChars) 字")
                if state.otherDevicesTodayKeystrokes > 0 {
                    Text("·")
                    Text("其他设备 \(otherDevicesChars) 字")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            HStack(spacing: 6) {
                Image(systemName: hardwareIconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
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
                    .frame(width: 14)
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
                    .frame(width: 14)
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
        hardware.snapshot.cpuTemperatureCelsius == nil ? "thermometer.sun" : "thermometer.medium"
    }

    private var hardwareLabelText: String {
        hardware.snapshot.cpuTemperatureCelsius == nil ? "系统热状态" : "CPU 温度"
    }

    private var hardwareValueText: String {
        if let value = hardware.snapshot.cpuTemperatureCelsius {
            return "\(Int(value.rounded()))°C"
        }

        switch hardware.snapshot.systemThermalState {
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
        guard let memoryStats = hardware.snapshot.memoryStats else { return "不可用" }
        return formatBytes(memoryStats.appResidentBytes)
    }

    private var systemMemoryText: String {
        guard let memoryStats = hardware.snapshot.memoryStats else { return "不可用" }
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
        .controlSize(.small)
    }

    /// LSUIElement (menu-bar) apps don't activate or raise windows on their own,
    /// so `openWindow` alone leaves the window behind other apps. Activate the
    /// app and force the main window to the front on the next run-loop tick
    /// (after `openWindow` has created/registered it).
    private func openMainWindow() {
        dismissMenu()
        state.prepareToOpenMainWindow()
        NSApp.setActivationPolicy(.regular)
        showMainWindow()
        DispatchQueue.main.async {
            state.prepareToOpenMainWindow()
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }
}
