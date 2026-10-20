import Foundation

enum CDMEvent {
    case status(String)
    case started(Int, Int)
    case finished(Int, Int, IOResult)
}

struct CDMOutcome {
    var results: [[IOResult?]]
    var report: String
    var error: String?
    var stopped: Bool
}

enum CDMEngine {
    static func run(sizeMB: Int,
                    passes: Int,
                    mixReadPercent: Int,
                    direct: Bool,
                    token: StopToken,
                    fileURL: URL,
                    event: @escaping (CDMEvent) -> Void) -> CDMOutcome {
        let size = Int64(max(64, sizeMB)) * 1_048_576
        let passCount = max(1, passes)
        var results = [[IOResult?]](repeating: [IOResult?](repeating: nil, count: 3),
                                    count: CDMCatalog.rows.count)
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

            for pass in 1...passCount {
                if token.isStopped { break }
                for row in CDMCatalog.rows {
                    if token.isStopped { break }
                    for column in 0..<3 {
                        if token.isStopped { break }
                        let columnName: String
                        let pattern: IOPattern
                        switch column {
                        case 0:
                            columnName = "Read"
                            pattern = .read
                        case 1:
                            columnName = "Write"
                            pattern = .write
                        default:
                            columnName = "Mix"
                            pattern = .mixed(readPercent: mixReadPercent)
                        }

                        event(.status("CDM \(pass)/\(passCount) · \(row.title) · \(columnName)"))
                        event(.started(row.id, column))

                        let spec = IOSpec(name: "\(row.title) \(columnName)",
                                          blockSize: row.blockSize,
                                          qd: row.qd,
                                          threads: row.threads,
                                          pattern: pattern,
                                          duration: 8,
                                          isSequential: row.id < 2)
                        let result = DiskIO.measure(fd: fd, fileSize: size, spec: spec, token: token)
                        results[row.id][column] = result
                        event(.finished(row.id, column, result))
                    }
                }
            }
        } catch {
            errorText = error.localizedDescription
            event(.status("出错：\(error.localizedDescription)"))
        }

        var lines: [String] = []
        lines.append("fio 存储测试 · CrystalDiskMark 风格（iOS / native-posix）")
        lines.append("数据大小 \(sizeMB) MiB · 测试 \(passCount) 次 · 混合 R\(mixReadPercent)/W\(100 - mixReadPercent) · direct=\(direct ? 1 : 0)")
        lines.append("引擎 native-posix (F_NOCACHE)")
        for row in CDMCatalog.rows {
            let cells = results[row.id]
            let read = cells[0]
            let write = cells[1]
            let mix = cells[2]
            lines.append(String(format: "%@ · 读 %.1f / 写 %.1f / 混合 %.1f MB/s",
                                row.title,
                                read?.readBW ?? 0,
                                write?.writeBW ?? 0,
                                mix?.totalBW ?? 0))
        }
        if let errorText { lines.append("错误: \(errorText)") }

        return CDMOutcome(results: results,
                          report: lines.joined(separator: "\n"),
                          error: errorText,
                          stopped: token.isStopped)
    }
}
