import SwiftUI

struct TopAppView: View {
    var isActive: Bool = true

    @State private var groups: [DeviceAppStats] = []

    var body: some View {
        if isActive {
            content
        } else {
            Color.clear
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日应用排行").font(.headline)

            if groups.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "app.dashed").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("今天还没有记录").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            deviceSection(group)
                        }
                    }
                    .padding(.trailing, 12)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: reload)
    }

    private var factor: Double { CharEstimate.factor }

    /// Only label each section with its device when there's more than one — with a
    /// single device the header would just be noise.
    private var showsDeviceHeaders: Bool { groups.count > 1 }

    private func chars(_ app: AppStat) -> Int {
        CharEstimate.characters(fromKeystrokes: app.keystrokes, factor: factor)
    }

    /// Global max across every device, so bar lengths are comparable device-to-device.
    private var maxTotal: Int {
        max(groups.flatMap { $0.apps }.map(chars).max() ?? 1, 1)
    }

    private func deviceSection(_ group: DeviceAppStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsDeviceHeaders {
                HStack(spacing: 6) {
                    Image(systemName: group.isSelf ? "desktopcomputer" : "laptopcomputer")
                    Text(group.isSelf ? "\(group.deviceName)（本机）" : group.deviceName)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            ForEach(Array(group.apps.enumerated()), id: \.element.bundleId) { index, app in
                row(rank: index + 1, app: app, group: group)
            }
        }
    }

    private func row(rank: Int, app: AppStat, group: DeviceAppStats) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.appName).fontWeight(.medium).lineLimit(1)
                    Spacer()
                    Text("\(chars(app)) 字")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(DeviceColor.color(for: group.id, isSelf: group.isSelf).opacity(0.35))
                        .frame(width: max(4, geo.size.width * CGFloat(chars(app)) / CGFloat(maxTotal)))
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MergedStats().topAppsTodayByDevice(limit: 10)
            DispatchQueue.main.async {
                groups = result
            }
        }
    }
}
