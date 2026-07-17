import Combine

struct DashboardStatsSnapshot: Equatable {
    let todayKeystrokes: Int
    let otherDevicesTodayKeystrokes: Int
    let keystrokesPerCharacter: Double
    let deviceCount: Int

    var todayKeystrokesMerged: Int {
        todayKeystrokes + otherDevicesTodayKeystrokes
    }
}

@MainActor
final class DashboardStatsModel: ObservableObject {
    @Published private(set) var snapshot = DashboardStatsSnapshot(
        todayKeystrokes: 0,
        otherDevicesTodayKeystrokes: 0,
        keystrokesPerCharacter: CharEstimate.defaultFactor,
        deviceCount: 1
    )

    func update(
        todayKeystrokes: Int,
        otherDevicesTodayKeystrokes: Int,
        keystrokesPerCharacter: Double,
        deviceCount: Int
    ) {
        let next = DashboardStatsSnapshot(
            todayKeystrokes: todayKeystrokes,
            otherDevicesTodayKeystrokes: otherDevicesTodayKeystrokes,
            keystrokesPerCharacter: keystrokesPerCharacter,
            deviceCount: max(deviceCount, 1)
        )
        if snapshot != next {
            snapshot = next
        }
    }
}
