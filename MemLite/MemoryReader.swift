import Darwin
import Foundation

enum MemoryReadError: Error {
    case physicalMemory
    case pageSize
    case vmStatistics
    case swap
    case pressure
}

enum MemoryReader {
    #if DEBUG
    static var debugReadCount = 0
    #endif

    static func read() throws -> MemorySnapshot {
        #if DEBUG
        debugReadCount += 1
        #endif
        let physicalBytes = try sysctlInteger("hw.memsize", as: UInt64.self, error: .physicalMemory)
        let pageSize = try hostPageSize()
        let statistics = try vmStatistics()
        let swapBytes = try swapUsedBytes()
        let pressureValue = try sysctlInteger(
            "kern.memorystatus_vm_pressure_level",
            as: Int32.self,
            error: .pressure
        )

        let appPages = subtracting(statistics.internal_page_count, statistics.purgeable_count)
        let cachedPages = statistics.external_page_count + statistics.purgeable_count

        return MemorySnapshot(
            physicalBytes: physicalBytes,
            cachedBytes: bytes(fromPages: cachedPages, pageSize: pageSize),
            swapBytes: swapBytes,
            appBytes: bytes(fromPages: appPages, pageSize: pageSize),
            wiredBytes: bytes(fromPages: statistics.wire_count, pageSize: pageSize),
            compressedBytes: bytes(fromPages: statistics.compressor_page_count, pageSize: pageSize),
            pressure: MemoryPressureLevel(systemValue: pressureValue)
        )
    }

    private static func hostPageSize() throws -> UInt64 {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            throw MemoryReadError.pageSize
        }
        return UInt64(pageSize)
    }

    private static func vmStatistics() throws -> vm_statistics64 {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MemoryReadError.vmStatistics
        }
        return statistics
    }

    private static func swapUsedBytes() throws -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else {
            throw MemoryReadError.swap
        }
        return usage.xsu_used
    }

    private static func sysctlInteger<T: FixedWidthInteger>(
        _ name: String,
        as type: T.Type,
        error: MemoryReadError
    ) throws -> T {
        var value = T.zero
        var size = MemoryLayout<T>.stride
        let result = name.withCString { pointer in
            sysctlbyname(pointer, &value, &size, nil, 0)
        }
        guard result == 0, size == MemoryLayout<T>.stride else {
            throw error
        }
        return value
    }

    private static func bytes(fromPages pages: UInt32, pageSize: UInt64) -> UInt64 {
        UInt64(pages) * pageSize
    }

    private static func subtracting(_ lhs: UInt32, _ rhs: UInt32) -> UInt32 {
        lhs > rhs ? lhs - rhs : 0
    }
}
