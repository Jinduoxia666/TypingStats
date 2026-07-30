import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var fixedInputSource: FixedInputSourceController

    var body: some View {
        TabView {
            general.tabItem { Label("通用", systemImage: "gear") }
            ExcludedAppsView().tabItem { Label("应用", systemImage: "app.dashed") }
            SyncView().tabItem { Label("同步", systemImage: "icloud") }
            ExportView().tabItem { Label("数据", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 480, height: 400)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("TypingStats 记录你每天输入的字数。", systemImage: "keyboard")
                .font(.headline)

            Stepper(value: $state.keystrokesPerCharacter, in: 1.0...6.0, step: 0.5) {
                HStack {
                    Text("平均每字按键数")
                    Spacer()
                    Text(String(format: "%.1f", state.keystrokesPerCharacter))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("固定输入法", isOn: $fixedInputSource.isEnabled)

            Picker("输入法", selection: $fixedInputSource.selectedInputSourceID) {
                ForEach(fixedInputSource.availableInputSources) { inputSource in
                    Text(inputSource.name).tag(inputSource.id)
                }
            }
            .disabled(fixedInputSource.availableInputSources.isEmpty)

            Text("启用后，切换到其他输入法时会自动恢复为所选输入法。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("剪贴板历史快捷键")
                Spacer()
                ShortcutRecorderButton(
                    shortcut: $state.clipboardShortcut,
                    onRecordingChanged: state.setShortcutRecording
                )
            }

            HStack {
                Text("时间戳转换快捷键")
                Spacer()
                ShortcutRecorderButton(
                    shortcut: $state.timestampShortcut,
                    onRecordingChanged: state.setShortcutRecording
                )
            }

            Text("字数 = 计入的按键数 ÷ 该系数。只统计 a–z、A–Z、0–9,标点/空格/回车/方向键不计入。中文拼音一般设 2–3;纯英文可设 1。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("统计完全在本地进行,不上传任何内容。在「应用」标签页可排除不想统计的 app。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text(versionText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "版本 \(version) (\(build))"
    }
}

private struct ShortcutRecorderButton: View {
    @Binding var shortcut: ClipboardShortcut
    let onRecordingChanged: (Bool) -> Void
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "按下快捷键..." : shortcut.displayText) {
            toggleRecording()
        }
        .buttonStyle(.bordered)
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        onRecordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let newShortcut = ClipboardShortcut(event: event)
            guard newShortcut.isUsable else { return nil }
            shortcut = newShortcut
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        onRecordingChanged(false)
    }
}
