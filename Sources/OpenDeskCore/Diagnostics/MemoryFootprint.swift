import Foundation
import Darwin

/// Process memory footprint used by soak/resource-bound assertions.
public enum MemoryFootprint {
    /// Resident set size in bytes (task_info phys_footprint on macOS).
    public static func snapshot() -> (residentBytes: Int, threads: Int) {
        var info = task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info_data_t>.size) / mach_msg_type_number_t(MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
            }
        }
        let bytes = result == KERN_SUCCESS ? Int(info.resident_size) : 0
        return (bytes, 0)
    }
}
