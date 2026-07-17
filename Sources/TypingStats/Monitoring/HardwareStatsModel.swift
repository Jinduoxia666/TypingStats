import Combine
import Foundation

struct HardwareStatsSnapshot: Equatable {
    let cpuTemperatureCelsius: Double?
    let systemThermalState: ProcessInfo.ThermalState
    let memoryStats: MemoryStats?
}

@MainActor
final class HardwareStatsModel: ObservableObject {
    @Published private(set) var snapshot = HardwareStatsSnapshot(
        cpuTemperatureCelsius: nil,
        systemThermalState: ProcessInfo.processInfo.thermalState,
        memoryStats: nil
    )

    func update(
        cpuTemperatureCelsius: Double?,
        systemThermalState: ProcessInfo.ThermalState,
        memoryStats: MemoryStats?
    ) {
        let roundedTemperature = cpuTemperatureCelsius.map { Double(Int($0.rounded())) }
        let displayedMemory = Self.hasSameDisplayValue(snapshot.memoryStats, memoryStats)
            ? snapshot.memoryStats
            : memoryStats
        let next = HardwareStatsSnapshot(
            cpuTemperatureCelsius: roundedTemperature,
            systemThermalState: systemThermalState,
            memoryStats: displayedMemory
        )
        if snapshot != next {
            snapshot = next
        }
    }

    private static func hasSameDisplayValue(_ lhs: MemoryStats?, _ rhs: MemoryStats?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return displayBucket(lhs.appResidentBytes) == displayBucket(rhs.appResidentBytes)
                && displayBucket(lhs.systemUsedBytes) == displayBucket(rhs.systemUsedBytes)
                && displayBucket(lhs.systemTotalBytes) == displayBucket(rhs.systemTotalBytes)
        default:
            return false
        }
    }

    private static func displayBucket(_ bytes: UInt64) -> ByteDisplayBucket {
        let value = Double(bytes)
        let gigabytes = value / 1_073_741_824
        if gigabytes >= 1 {
            return ByteDisplayBucket(unit: .gigabytes, roundedValue: Int((gigabytes * 10).rounded()))
        }
        return ByteDisplayBucket(unit: .megabytes, roundedValue: Int((value / 1_048_576).rounded()))
    }
}

private struct ByteDisplayBucket: Equatable {
    enum Unit: Equatable {
        case megabytes
        case gigabytes
    }

    let unit: Unit
    let roundedValue: Int
}
