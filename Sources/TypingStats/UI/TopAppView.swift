import SwiftUI

struct TopAppView: View {
    @State private var apps: [AppStat] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日应用排行").font(.headline)

            if apps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "app.dashed").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("今天还没有记录").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(apps.enumerated()), id: \.element.bundleId) { index, app in
                            row(rank: index + 1, app: app)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: reload)
    }

    private var factor: Double { CharEstimate.factor }

    private func chars(_ app: AppStat) -> Int {
        CharEstimate.characters(fromKeystrokes: app.keystrokes, factor: factor)
    }

    private var maxTotal: Int {
        max(apps.map(chars).max() ?? 1, 1)
    }

    private func row(rank: Int, app: AppStat) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.appName).fontWeight(.medium).lineLimit(1)
                    Spacer()
                    Text("\(chars(app)) 字").monospacedDigit().foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: max(4, geo.size.width * CGFloat(chars(app)) / CGFloat(maxTotal)))
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() {
        apps = MergedStats().topAppsToday(limit: 10)
    }
}
