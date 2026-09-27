import Foundation
import MachO

struct MemoryStats: Equatable {
    let appResidentBytes: UInt64
    let systemUsedBytes: UInt64
    let systemTotalBytes: UInt64
}

struct MemoryStatsReader {
    func read() -> MemoryStats? {
        guard let appResidentBytes = appPhysicalFootprintBytes(),
              let systemUsedBytes = systemUsedBytes() else {
            return nil
        }

        return MemoryStats(
            appResidentBytes: appResidentBytes,
            systemUsedBytes: systemUsedBytes,
            systemTotalBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    private func appPhysicalFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }

    private func systemUsedBytes() -> UInt64? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(
                    host,
                    HOST_VM_INFO64,
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let usedPages = UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return usedPages * UInt64(pageSize)
    }
}
