import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            general.tabItem { Label("通用", systemImage: "gear") }
            ExcludedAppsView().tabItem { Label("应用", systemImage: "app.dashed") }
            SyncView().tabItem { Label("同步", systemImage: "icloud") }
            ExportView().tabItem { Label("数据", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 480, height: 340)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("TypingStats 估算你每天输入的字数。", systemImage: "keyboard")
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

            Text("字数 = 计入的按键数 ÷ 该系数。只统计 a–z、A–Z、0–9,标点/空格/回车/方向键不计入。中文拼音一般设 2–3;纯英文可设 1。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("统计完全在本地进行,不上传任何内容。在「应用」标签页可排除不想统计的 app。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
