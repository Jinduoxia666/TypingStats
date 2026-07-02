import SwiftUI
import AppKit

struct ExcludedAppsView: View {
    @EnvironmentObject private var state: AppState
    @State private var apps: [AppEntry] = []

    struct AppEntry: Identifiable {
        let id: String   // bundle id
        let name: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("被排除的 app 不会统计其输入(例如密码管理器、游戏)。")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(apps) { app in
                Toggle(isOn: binding(for: app.id)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                        Text(app.id).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .padding()
        .onAppear(perform: reload)
    }

    private func binding(for bundleId: String) -> Binding<Bool> {
        Binding(
            get: { state.excludedBundleIds.contains(bundleId) },
            set: { state.setExcluded(bundleId, excluded: $0) }
        )
    }

    /// Merge apps that have recorded stats, currently-running apps, and any
    /// already-excluded ids — so anything worth excluding shows up.
    private func reload() {
        var merged: [String: String] = [:]

        for app in MergedStats().knownApps() {
            merged[app.bundleId] = app.name
        }
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier {
                merged[id] = app.localizedName ?? id
            }
        }
        for id in state.excludedBundleIds where merged[id] == nil {
            merged[id] = id
        }

        apps = merged
            .map { AppEntry(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
