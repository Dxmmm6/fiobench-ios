import Foundation

enum ASSSDEvent {
    case status(String)
    case started(Int)
    case finished(Int, IOResult)
}

struct ASSSDOutcome {
    var results: [IOResult?]
    var readScore: Double
    var writeScore: Double
    var totalScore: Double
    var report: String
    var error: String?
    var stopped: Bool
}

enum ASSSDEngine {
    static func run(direct: Bool,
                    token: StopToken,
                    fileURL: URL,
                    event: @escaping (ASSSDEvent) -> Void) -> ASSSDOutcome {
        let size = Int64(1024) * 1_048_576
        var results = [IOResult?](repeating: nil, count: 6)
        var fd: Int32 = -1
        var errorText: String?

        defer {
            if fd >= 0 { close(fd) }
            try? FileManager.default.removeItem(at: fileURL)
        }

        let jobs: [(title: String, block: Int, qd: Int, sequential: Bool, read: Bool)] = [
            ("Seq 1M QD32 读", 1 << 20, 32, true, true),
            ("Seq 1M QD32 写", 1 << 20, 32, true, false),
            ("4K QD1 读", 4096, 1, false, true),
            ("4K QD1 写", 4096, 1, false, false),
            ("4K-64Thrd 读", 4096, 64, false, true),
            ("4K-64Thrd 写", 4096, 64, false, false)
        ]

        do {
            fd = try DiskIO.openWritable(url: fileURL, size: size, direct: direct)
            event(.status("AS SSD 准备 1024 MB 文件…"))
            try DiskIO.fill(fd: fd, size: size, token: token) { fraction in
                event(.status(String(format: "AS SSD 准备文件 %.0f%%", fraction * 100)))
            }

            for (index, job) in jobs.enumerated() {
                if token.isStopped { break }
                event(.status("AS SSD \(index + 1)/6 · \(job.title)"))
                event(.started(index))
                let spec = IOSpec(name: job.title,
                                  blockSize: job.block,
                                  qd: job.qd,
                                  threads: 1,
                                  pattern: job.read ? .read : .write,
                                  duration: 8,
                                  isSequential: job.sequential)
                let result = DiskIO.measure(fd: fd, fileSize: size, spec: spec, token: token)
                results[index] = result
                event(.finished(index, result))
            }
        } catch {
            errorText = error.localizedDescription
            event(.status("出错：\(error.localizedDescription)"))
        }

        let seqR = results[0]?.readBW ?? 0
        let seqW = results[1]?.writeBW ?? 0
        let r4R = results[2]?.readBW ?? 0
        let r4W = results[3]?.writeBW ?? 0
        let r64R = results[4]?.readBW ?? 0
        let r64W = results[5]?.writeBW ?? 0

        let readScore = 0.2 * seqR + 8.0 * r4R + 0.8 * r64R
        let writeScore = 0.2 * seqW + 12.0 * r4W + 0.8 * r64W
        let totalScore = readScore + writeScore

        var lines: [String] = []
        lines.append("fio 存储测试 · AS SSD 风格（iOS / native-posix）")
        lines.append("固定 1024 MB · direct=\(direct ? 1 : 0) · 每项 8 秒")
        lines.append("引擎 native-posix (F_NOCACHE)")
        lines.append(String(format: "SEQ 读 %.1f / 写 %.1f MB/s", seqR, seqW))
        lines.append(String(format: "4K QD1 读 %.1f / 写 %.1f MB/s，延迟 %.0f / %.0f µs",
                            r4R, r4W, results[2]?.averageLatencyUS ?? 0, results[3]?.averageLatencyUS ?? 0))
        lines.append(String(format: "4K-64Thrd 读 %.1f / 写 %.1f MB/s", r64R, r64W))
        lines.append(String(format: "读分 %.0f · 写分 %.0f · 总分 %.0f", readScore, writeScore, totalScore))
        if let errorText { lines.append("错误: \(errorText)") }

        return ASSSDOutcome(results: results,
                            readScore: readScore,
                            writeScore: writeScore,
                            totalScore: totalScore,
                            report: lines.joined(separator: "\n"),
                            error: errorText,
                            stopped: token.isStopped)
    }
}
