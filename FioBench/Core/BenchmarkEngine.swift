import Foundation
import Darwin

enum BenchEvent {
    case status(String)
    case started(Int)
    case finished(Int, IOResult)
}

struct BenchOutcome {
    var results: [IOResult?]
    var score: Double
    var report: String
    var stopped: Bool
    var error: String?
}

enum BenchmarkEngine {
    static func run(sizeMB: Int,
                    direct: Bool,
                    gapSeconds: Double,
                    token: StopToken,
                    fileURL: URL,
                    event: @escaping (BenchEvent) -> Void) -> BenchOutcome {
        let size = Int64(max(64, sizeMB)) * 1_048_576
        var results = [IOResult?](repeating: nil, count: BenchCatalog.definitions.count)
        var fd: Int32 = -1
        var errorText: String?

        defer {
            if fd >= 0 { close(fd) }
            try? FileManager.default.removeItem(at: fileURL)
        }

        do {
            fd = try DiskIO.openWritable(url: fileURL, size: size, direct: direct)
            event(.status("准备测试文件 \(sizeMB) MB…"))
            try DiskIO.fill(fd: fd, size: size, token: token) { fraction in
                event(.status(String(format: "准备测试文件 %.0f%%", fraction * 100)))
            }

            for definition in BenchCatalog.definitions {
                if token.isStopped { break }
                event(.status("基准 \(definition.index + 1)/14 · \(definition.name)"))
                event(.started(definition.index))

                let spec = IOSpec(name: definition.name,
                                  blockSize: definition.blockSize,
                                  qd: definition.qd,
                                  threads: definition.threads,
                                  pattern: definition.pattern,
                                  duration: 8,
                                  isSequential: definition.index < 2)
                let result = DiskIO.measure(fd: fd, fileSize: size, spec: spec, token: token)
                results[definition.index] = result
                event(.finished(definition.index, result))

                if definition.index < BenchCatalog.definitions.count - 1 && gapSeconds > 0 && !token.isStopped {
                    event(.status("冷却 \(Int(gapSeconds)) 秒…"))
                    var remaining = gapSeconds
                    while remaining > 0 && !token.isStopped {
                        let slice = min(0.1, remaining)
                        Thread.sleep(forTimeInterval: slice)
                        remaining -= slice
                    }
                }
            }
        } catch {
            errorText = error.localizedDescription
            event(.status("出错：\(error.localizedDescription)"))
        }

        var logSum = 0.0
        var usable = 0
        for (index, definition) in BenchCatalog.definitions.enumerated() {
            guard let result = results[index], result.isUsable else { continue }
            let ratio = max(result.totalBW / definition.referenceBW, 0.02)
            logSum += definition.weight * log(ratio)
            usable += 1
        }

        let score = usable > 0 ? 1000.0 * exp(logSum / BenchCatalog.totalWeight) : 0
        let report = makeReport(sizeMB: sizeMB, direct: direct, gap: gapSeconds,
                                results: results, score: score, error: errorText)

        return BenchOutcome(results: results, score: score, report: report,
                            stopped: token.isStopped, error: errorText)
    }

    private static func makeReport(sizeMB: Int, direct: Bool, gap: Double,
                                   results: [IOResult?], score: Double,
                                   error: String?) -> String {
        var lines: [String] = []
        lines.append("fio 存储测试 · 基准（iOS / native-posix）")
        lines.append("文件 \(sizeMB) MB · direct=\(direct ? 1 : 0) · 间隔 \(Int(gap))s")
        lines.append("引擎 native-posix (F_NOCACHE)")
        for (index, definition) in BenchCatalog.definitions.enumerated() {
            if let result = results[index], result.isUsable {
                lines.append(String(format: "%@: %.1f MB/s · %.0f IOPS",
                                    definition.name, result.totalBW, result.totalIOPS))
            } else {
                lines.append("\(definition.name): 失败")
            }
        }
        lines.append(String(format: "综合得分 = %.0f", score))
        if let error { lines.append("错误: \(error)") }
        return lines.joined(separator: "\n")
    }
}
