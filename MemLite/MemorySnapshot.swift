import Foundation

enum MemoryPressureLevel: Equatable {
    case normal
    case warning
    case urgent
    case critical

    var isDanger: Bool {
        switch self {
        case .urgent, .critical:
            return true
        case .normal, .warning:
            return false
        }
    }

    init(systemValue: Int32) {
        switch systemValue {
        case 0x1:
            self = .normal
        case 0x2:
            self = .warning
        case 0x4:
            self = .urgent
        case 0x8:
            self = .critical
        default:
            self = .normal
        }
    }
}

struct MemorySnapshot {
    let physicalBytes: UInt64
    let cachedBytes: UInt64
    let swapBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let pressure: MemoryPressureLevel

    var usedBytes: UInt64 {
        appBytes + wiredBytes + compressedBytes
    }

    var menuBarText: String {
        let used = Self.gigabytes(usedBytes, fractionDigits: 1)
        let physical = Self.gigabytes(physicalBytes, fractionDigits: 1)
        return "\(used) / \(physical) GB"
    }

    var detailLines: [MemoryDetailLine] {
        [
            MemoryDetailLine(name: "물리적 메모리", value: Self.detailGigabytes(physicalBytes)),
            MemoryDetailLine(name: "사용된 메모리", value: Self.detailGigabytes(usedBytes)),
            MemoryDetailLine(name: "캐시된 파일", value: Self.detailGigabytes(cachedBytes)),
            MemoryDetailLine(name: "사용된 스왑 공간", value: Self.swapText(swapBytes)),
            MemoryDetailLine(name: "앱 메모리", value: Self.detailGigabytes(appBytes)),
            MemoryDetailLine(name: "와이어드 메모리", value: Self.detailGigabytes(wiredBytes)),
            MemoryDetailLine(name: "압축됨", value: Self.detailGigabytes(compressedBytes)),
        ]
    }

    private static func detailGigabytes(_ bytes: UInt64) -> String {
        "\(MemoryByteFormat.gigabytes(bytes, fractionDigits: 2))GB"
    }

    private static func swapText(_ bytes: UInt64) -> String {
        MemoryByteFormat.detail(bytes)
    }

    private static func gigabytes(_ bytes: UInt64, fractionDigits: Int) -> String {
        MemoryByteFormat.gigabytes(bytes, fractionDigits: fractionDigits)
    }
}

enum MemoryByteFormat {
    static func detail(_ bytes: UInt64) -> String {
        bytes == 0 ? "0바이트" : "\(gigabytes(bytes, fractionDigits: 2))GB"
    }

    static func gigabytes(_ bytes: UInt64, fractionDigits: Int) -> String {
        let value = Decimal(bytes) / Decimal(1_073_741_824)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }
}

struct MemoryDetailLine: Equatable {
    let name: String
    let value: String
}
