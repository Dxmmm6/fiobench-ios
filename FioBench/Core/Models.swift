import Foundation

// MARK: - Tabs

enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case bench = 0
    case cdm
    case assd
    case custom
    case stress
    case raw

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .bench: return "基准"
        case .cdm: return "CDM"
        case .assd: return "AS SSD"
        case .custom: return "自定义"
        case .stress: return "压力"
        case .raw: return "裸读"
        }
    }
}

// MARK: - Common parameters

enum StorageTarget: String, CaseIterable, Identifiable, Hashable {
    case builtin = "内置存储"
    case external = "外置 SD"

    var id: String { rawValue }
    var isAvailable: Bool { self == .builtin }
}

enum ItemState: Equatable {
    case pending
    case running
    case ok
    case failed
}

// MARK: - Measured result

struct IOResult {
    var readBytes: Int64 = 0
    var writeBytes: Int64 = 0
    var readOps: Int64 = 0
    var writeOps: Int64 = 0
    var readLatencyNS: Double = 0
    var writeLatencyNS: Double = 0
    var elapsed: Double = 0
    var error: String? = nil

    var totalBytes: Int64 { readBytes + writeBytes }
    var totalOps: Int64 { readOps + writeOps }

    var readBW: Double {
        guard elapsed > 0 else { return 0 }
        return Double(readBytes) / 1_048_576.0 / elapsed
    }

    var writeBW: Double {
        guard elapsed > 0 else { return 0 }
        return Double(writeBytes) / 1_048_576.0 / elapsed
    }

    var readIOPS: Double {
        guard elapsed > 0 else { return 0 }
        return Double(readOps) / elapsed
    }

    var writeIOPS: Double {
        guard elapsed > 0 else { return 0 }
        return Double(writeOps) / elapsed
    }

    var totalBW: Double { readBW + writeBW }
    var totalIOPS: Double { readIOPS + writeIOPS }

    var readLatencyUS: Double {
        guard readOps > 0 else { return 0 }
        return readLatencyNS / Double(readOps) / 1_000.0
    }

    var writeLatencyUS: Double {
        guard writeOps > 0 else { return 0 }
        return writeLatencyNS / Double(writeOps) / 1_000.0
    }

    var averageLatencyUS: Double {
        guard totalOps > 0 else { return 0 }
        return (readLatencyNS + writeLatencyNS) / Double(totalOps) / 1_000.0
    }

    var isUsable: Bool { totalBytes > 0 && error == nil }
}

// MARK: - Benchmark catalogue

struct BenchDefinition {
    let index: Int
    let name: String
    let sub: String
    let blockSize: Int
    let qd: Int
    let threads: Int
    let pattern: IOPattern
    let weight: Double
    let referenceBW: Double
}

enum BenchCatalog {
    static let definitions: [BenchDefinition] = [
        .init(index: 0,  name: "顺序读 1M", sub: "QD32 T1", blockSize: 1 << 20, qd: 32, threads: 1, pattern: .read, weight: 5.0, referenceBW: 1200),
        .init(index: 1,  name: "顺序写 1M", sub: "QD32 T1", blockSize: 1 << 20, qd: 32, threads: 1, pattern: .write, weight: 5.0, referenceBW: 600),
        .init(index: 2,  name: "4K Q1T1 读", sub: "QD1 T1", blockSize: 4096, qd: 1, threads: 1, pattern: .read, weight: 10.0, referenceBW: 25),
        .init(index: 3,  name: "4K Q1T1 写", sub: "QD1 T1", blockSize: 4096, qd: 1, threads: 1, pattern: .write, weight: 10.0, referenceBW: 20),
        .init(index: 4,  name: "4K Q1T1 混合", sub: "QD1 T1 · R70/W30", blockSize: 4096, qd: 1, threads: 1, pattern: .mixed(readPercent: 70), weight: 10.0, referenceBW: 22),
        .init(index: 5,  name: "4K Q2T1 读", sub: "QD2 T1", blockSize: 4096, qd: 2, threads: 1, pattern: .read, weight: 6.667, referenceBW: 45),
        .init(index: 6,  name: "4K Q2T1 写", sub: "QD2 T1", blockSize: 4096, qd: 2, threads: 1, pattern: .write, weight: 6.667, referenceBW: 35),
        .init(index: 7,  name: "4K Q2T1 混合", sub: "QD2 T1 · R70/W30", blockSize: 4096, qd: 2, threads: 1, pattern: .mixed(readPercent: 70), weight: 6.667, referenceBW: 38),
        .init(index: 8,  name: "4K Q4T1 读", sub: "QD4 T1", blockSize: 4096, qd: 4, threads: 1, pattern: .read, weight: 6.667, referenceBW: 70),
        .init(index: 9,  name: "4K Q4T1 写", sub: "QD4 T1", blockSize: 4096, qd: 4, threads: 1, pattern: .write, weight: 6.667, referenceBW: 55),
        .init(index: 10, name: "4K Q4T1 混合", sub: "QD4 T1 · R70/W30", blockSize: 4096, qd: 4, threads: 1, pattern: .mixed(readPercent: 70), weight: 6.667, referenceBW: 60),
        .init(index: 11, name: "4K Q4T4 读", sub: "QD4 T4", blockSize: 4096, qd: 4, threads: 4, pattern: .read, weight: 6.667, referenceBW: 180),
        .init(index: 12, name: "4K Q4T4 写", sub: "QD4 T4", blockSize: 4096, qd: 4, threads: 4, pattern: .write, weight: 6.667, referenceBW: 140),
        .init(index: 13, name: "4K Q4T4 混合", sub: "QD4 T4 · R70/W30", blockSize: 4096, qd: 4, threads: 4, pattern: .mixed(readPercent: 70), weight: 6.667, referenceBW: 150)
    ]

    static var initialItems: [BenchItem] {
        definitions.map {
            BenchItem(id: $0.index, name: $0.name, sub: $0.sub, weight: $0.weight,
                      referenceBW: $0.referenceBW, state: .pending, result: nil)
        }
    }

    static var totalWeight: Double {
        definitions.reduce(0) { $0 + $1.weight }
    }
}

struct BenchItem: Identifiable {
    let id: Int
    let name: String
    let sub: String
    let weight: Double
    let referenceBW: Double
    var state: ItemState
    var result: IOResult?
}

// MARK: - CDM catalogue

struct CDMRowDefinition: Identifiable {
    let id: Int
    let title: String
    let blockSize: Int
    let qd: Int
    let threads: Int
}

enum CDMCatalog {
    static let rows: [CDMRowDefinition] = [
        .init(id: 0, title: "SEQ1M Q8T1", blockSize: 1 << 20, qd: 8, threads: 1),
        .init(id: 1, title: "SEQ1M Q1T1", blockSize: 1 << 20, qd: 1, threads: 1),
        .init(id: 2, title: "RND4K Q32T1", blockSize: 4096, qd: 32, threads: 1),
        .init(id: 3, title: "RND4K Q1T1", blockSize: 4096, qd: 1, threads: 1)
    ]

    static let sizeOptions: [(label: String, mb: Int)] = [
        ("64 MiB", 64), ("128 MiB", 128), ("256 MiB", 256),
        ("512 MiB", 512), ("1 GiB", 1024), ("2 GiB", 2048)
    ]

    static let mixOptions: [(label: String, readPercent: Int)] = [
        ("R70/W30", 70), ("R50/W50", 50), ("R90/W10", 90), ("R30/W70", 30)
    ]
}

// MARK: - Custom results

struct CustomEntry: Identifiable {
    let id = UUID()
    let title: String
    let result: IOResult?
    let failure: String?

    init(title: String, result: IOResult?, failure: String?) {
        self.title = title
        self.result = result
        self.failure = failure
    }
}

// MARK: - Stress

struct StressSnapshot {
    var totalBytes: Int64 = 0
    var writtenBytes: Int64 = 0
    var currentBw: Double = 0
    var averageBw: Double = 0
    var samples: [Double] = []
    var isRunning: Bool = false

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(writtenBytes) / Double(totalBytes)))
    }
}

// MARK: - Raw device

struct RawProbe {
    var path: String?
    var capacity: Int64
    var isRoot: Bool
    var message: String

    var isAvailable: Bool { path != nil && capacity > 0 }
}

// MARK: - Formatting

func formatBandwidth(_ mib: Double) -> String {
    guard mib > 0 else { return "--" }
    if mib >= 1024 { return String(format: "%.2f GB/s", mib / 1024.0) }
    if mib >= 100 { return String(format: "%.0f MB/s", mib) }
    return String(format: "%.1f MB/s", mib)
}

func formatIOPS(_ value: Double) -> String {
    guard value > 0 else { return "--" }
    if value >= 1_000_000 { return String(format: "%.2fM IOPS", value / 1_000_000) }
    if value >= 1000 { return String(format: "%.1fk IOPS", value / 1000) }
    return String(format: "%.0f IOPS", value)
}

func formatLatency(_ microseconds: Double) -> String {
    guard microseconds > 0 else { return "--" }
    if microseconds < 1000 { return String(format: "%.0f µs", microseconds) }
    return String(format: "%.2f ms", microseconds / 1000.0)
}

func formatBytes(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "--" }
    let gb = Double(bytes) / 1_073_741_824.0
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    return String(format: "%.0f MB", Double(bytes) / 1_048_576.0)
}
