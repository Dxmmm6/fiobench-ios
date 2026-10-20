import Foundation

enum IOPattern {
    case read
    case write
    case mixed(readPercent: Int)

    var readPercent: Int {
        switch self {
        case .read: return 100
        case .write: return 0
        case .mixed(let value): return max(0, min(100, value))
        }
    }
}

struct IOSpec {
    let name: String
    let blockSize: Int
    let qd: Int
    let threads: Int
    let pattern: IOPattern
    let duration: Double
    let isSequential: Bool

    init(name: String, blockSize: Int, qd: Int, threads: Int,
         pattern: IOPattern, duration: Double, isSequential: Bool) {
        self.name = name
        self.blockSize = blockSize
        self.qd = max(1, qd)
        self.threads = max(1, threads)
        self.pattern = pattern
        self.duration = max(0.1, duration)
        self.isSequential = isSequential
    }
}

final class StopToken {
    private let lock = NSLock()
    private var stopped = false

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
}

enum DiskError: LocalizedError {
    case cannotOpen(String, String)
    case io(String)
    case noSpace(required: Int64, available: Int64)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let path, let reason):
            return "无法打开 \(path)：\(reason)"
        case .io(let reason):
            return reason
        case .noSpace(let required, let available):
            return "空间不足：需要 \(formatBytes(required))，可用 \(formatBytes(available))"
        case .cancelled:
            return "已请求停止"
        }
    }
}

enum EnginePaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var base: URL {
        documents.appendingPathComponent("FioBench", isDirectory: true)
    }

    static var bench: URL {
        base.appendingPathComponent("bench", isDirectory: true)
    }

    static var history: URL {
        base.appendingPathComponent("history.txt")
    }

    static func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        try? fm.createDirectory(at: bench, withIntermediateDirectories: true)

        // Multi-gigabyte scratch files must never end up in an iCloud backup.
        var scratchDirectory = bench
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? scratchDirectory.setResourceValues(values)
    }

    static func clearBenchDirectory() {
        ensureDirectories()
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: bench, includingPropertiesForKeys: nil) else { return }
        for item in items {
            try? fm.removeItem(at: item)
        }
    }

    static func newTestFile(prefix: String = "fio_test") -> URL {
        ensureDirectories()
        clearBenchDirectory()
        return bench.appendingPathComponent("\(prefix)_\(UUID().uuidString).dat")
    }

    static func freeBytes() -> Int64 {
        ensureDirectories()
        guard let values = try? base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return 0
        }
        return Int64(available)
    }

    static func append(_ text: String, to url: URL) throws {
        ensureDirectories()
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    static func record(summary: String, detail: String) {
        let now = Date()
        let short = DateFormatter()
        short.dateFormat = "MM-dd HH:mm"
        let day = DateFormatter()
        day.dateFormat = "yyyyMMdd"
        let full = DateFormatter()
        full.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let historyURL = self.history
        let dailyURL = base.appendingPathComponent("fio_\(day.string(from: now)).txt")

        try? append("\(short.string(from: now))  \(summary)\n", to: historyURL)
        try? append("===== \(full.string(from: now)) =====\n\(detail)\n\n", to: dailyURL)
    }

    static func loadHistory(limit: Int = 12) -> [String] {
        guard let content = try? String(contentsOf: history, encoding: .utf8) else { return [] }
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)
            .map(String.init)
        return Array(lines.reversed())
    }

    static func directoryListing() -> String {
        guard let items = try? FileManager.default.contentsOfDirectory(at: bench, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "(无法读取)"
        }
        if items.isEmpty { return "(空)" }
        return items.map { $0.lastPathComponent }.joined(separator: "\n")
    }
}

final class StatsBox {
    private let lock = NSLock()
    private(set) var readBytes: Int64 = 0
    private(set) var writeBytes: Int64 = 0
    private(set) var readOps: Int64 = 0
    private(set) var writeOps: Int64 = 0
    private(set) var readLatencyNS: Double = 0
    private(set) var writeLatencyNS: Double = 0
    private(set) var firstError: String?

    func add(readBytes: Int64, writeBytes: Int64, readOps: Int64, writeOps: Int64,
             readLatencyNS: Double, writeLatencyNS: Double) {
        lock.lock()
        self.readBytes += readBytes
        self.writeBytes += writeBytes
        self.readOps += readOps
        self.writeOps += writeOps
        self.readLatencyNS += readLatencyNS
        self.writeLatencyNS += writeLatencyNS
        lock.unlock()
    }

    func setError(_ message: String) {
        lock.lock()
        if firstError == nil { firstError = message }
        lock.unlock()
    }
}
