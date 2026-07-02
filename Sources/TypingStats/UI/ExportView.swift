import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportView: View {
    @State private var message: String?

    private let exporter = StatsExporter()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("把全部历史数据导出为文件。包含:日期、当日按键数、估算字数、当日 Top app。")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("导出 CSV…") { export(.csv) }
                Button("导出 JSON…") { export(.json) }
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private enum Format { case csv, json }

    private func export(_ format: Format) {
        let panel = NSSavePanel()
        switch format {
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "TypingStats.csv"
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "TypingStats.json"
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try format == .csv ? exporter.csv() : exporter.json()
            try content.write(to: url, atomically: true, encoding: .utf8)
            message = "已导出到 \(url.path)"
        } catch {
            message = "导出失败:\(error.localizedDescription)"
        }
    }
}
