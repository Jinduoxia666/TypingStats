import SwiftUI

struct NetworkSpeedTestView: View {
    @StateObject private var model = NetworkSpeedTestModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                resultCards
                statusCard
                controls
                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("Apple 网络质量")
                .font(.title2)
                .fontWeight(.semibold)
            Text("使用 macOS 内置工具测试当前网络的速度与负载响应能力")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var resultCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("上次测试结果")
                    .font(.headline)
                Spacer()
                if model.isRunning, model.result != nil {
                    Text("正在更新…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                resultCard(
                    title: "响应能力",
                    value: formatted(model.result?.responsivenessRPM),
                    unit: "RPM",
                    systemImage: "waveform.path.ecg",
                    color: .purple
                )
                resultCard(
                    title: "下载",
                    value: formatted(model.result?.downloadMegabitsPerSecond),
                    unit: "Mbps",
                    systemImage: "arrow.down.circle.fill",
                    color: .blue
                )
                resultCard(
                    title: "上传",
                    value: formatted(model.result?.uploadMegabitsPerSecond),
                    unit: "Mbps",
                    systemImage: "arrow.up.circle.fill",
                    color: .green
                )
            }
        }
    }

    private func resultCard(
        title: String,
        value: String,
        unit: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(statusText)
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                if model.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let result = model.result {
                HStack(spacing: 16) {
                    detail("空闲延迟", String(format: "%.1f ms", result.idleLatencyMilliseconds))
                    detail("流量消耗", formattedBytes(result.totalBytesTransferred))
                    detail(
                        "下载 / 上传",
                        "\(formattedBytes(result.downloadBytesTransferred)) / \(formattedBytes(result.uploadBytesTransferred))"
                    )
                }
                HStack(spacing: 16) {
                    if let interfaceName = result.interfaceName {
                        detail("网络接口", interfaceName)
                    }
                    if let endpoint = result.testEndpoint {
                        detail("测试节点", endpoint)
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack {
            if model.isRunning {
                Button("取消", action: model.cancel)
            }
            Button(primaryButtonTitle, action: model.start)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.isRunning)
        }
    }

    private var footer: some View {
        Text("Apple 网络质量会产生测试流量，并行测量上下行容量和负载响应能力。RPM 越高表示交互响应越好，结果不会保存。")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private var statusText: String {
        switch model.phase {
        case .idle:
            return model.result == nil ? "准备开始测速" : "显示上次测试结果"
        case .testing:
            return model.result == nil
                ? "正在运行 Apple 网络质量测试…"
                : "正在运行新测试，上次结果暂时保留"
        case .completed:
            return "测速完成"
        case .failed:
            return "测速失败，请检查网络后重试"
        }
    }

    private var primaryButtonTitle: String {
        switch model.phase {
        case .idle:
            return "开始测速"
        case .completed, .failed:
            return "重新测速"
        case .testing:
            return "测速中"
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: bytes)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}
