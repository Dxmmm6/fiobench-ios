import Foundation

enum CustomEvent {
    case status(String)
    case progress(Double)
    case finished(CustomEntry)
}

struct CustomOutcome {
    var entries: [CustomEntry]
    var report: String
    var error: String?
    var stopped: Bool
}

enum CustomEngine {
    static func runSequential(blockSize: Int,
                              fileMB: Int,
                              direct: Bool,
                              token: StopToken,
                              fileURL: URL,
                              event: @escaping (CustomEvent) -> Void) -> CustomOutcome {
        let size = Int64(max(16, fileMB)) * 1_048_576
        var entries: [CustomEntry] = []
        var fd: Int32 = -1
        var errorText: String?

        defer {
            if fd >= 0 { close(fd) }
            try? FileManager.default.removeItem(at: fileURL)
        }

        do {
            fd = try DiskIO.openWritable(url: fileURL, size: size, direct: direct)

            event(.status("顺序 1/2 · 写 \(fileMB) MB"))
            let writeResult = DiskIO.measureFullFile(fd: fd, fileSize: size,
                                                     blockSize: blockSize, isWrite: true,
                                                     token: token) { event(.progress($0)) }
            let writeEntry = CustomEntry(title: "顺序写",
                                         result: writeResult.isUsable ? writeResult : nil,
                                         failure: writeResult.error)
            entries.append(writeEntry)
            event(.finished(writeEntry))

            if writeResult.isUsable && !token.isStopped {
                event(.status("顺序 2/2 · 读 \(fileMB) MB"))
                let readResult = DiskIO.measureFullFile(fd: fd, fileSize: size,
                                                        blockSize: blockSize, isWrite: false,
                                                        token: token) { event(.progress($0)) }
                let readEntry = CustomEntry(title: "顺序读",
                                            result: readResult.isUsable ? readResult : nil,
                                            failure: readResult.error)
                entries.append(readEntry)
                event(.finished(readEntry))
            }
        } catch {
            errorText = error.localizedDescription
            event(.status("出错：\(error.localizedDescription)"))
        }

        var lines = ["fio 存储测试 · 顺序读写（iOS / native-posix）"]
        lines.append("块大小 \(blockSize / 1024)K · 文件 \(fileMB) MB · direct=\(direct ? 1 : 0) · 跑完整个文件")
        for entry in entries {
            if let result = entry.result {
                lines.append(String(format: "%@: %.1f MB/s · %.0f IOPS · 延迟 %@",
                                    entry.title, result.totalBW, result.totalIOPS,
                                    formatLatency(result.averageLatencyUS)))
            } else {
                lines.append("\(entry.title): 失败 \(entry.failure ?? "")")
            }
        }
        if let errorText { lines.append("错误: \(errorText)") }

        return CustomOutcome(entries: entries, report: lines.joined(separator: "\n"),
                             error: errorText, stopped: token.isStopped)
    }

    static func runRandom(blockSize: Int,
                          qd: Int,
                          threads: Int,
                          duration: Double,
                          direct: Bool,
                          token: StopToken,
                          fileURL: URL,
                          event: @escaping (CustomEvent) -> Void) -> CustomOutcome {
        let size = Int64(1024) * 1_048_576
        var entries: [CustomEntry] = []
        var fd: Int32 = -1
        var errorText: String?

        defer {
            if fd >= 0 { close(fd) }
            try? FileManager.default.removeItem(at: fileURL)
        }

        do {
            fd = try DiskIO.openWritable(url: fileURL, size: size, direct: direct)
            event(.status("准备测试文件 1024 MB…"))
            try DiskIO.fill(fd: fd, size: size, token: token) { fraction in
                event(.status(String(format: "准备测试文件 %.0f%%", fraction * 100)))
            }

            let jobs: [(String, IOPattern)] = [
                ("随机写", .write),
                ("随机读", .read),
                ("混合70/30", .mixed(readPercent: 70))
            ]

            for (index, job) in jobs.enumerated() {
                if token.isStopped { break }
                event(.status("随机 \(index + 1)/3 · \(job.0)"))
                let spec = IOSpec(name: job.0,
                                  blockSize: blockSize,
                                  qd: qd,
                                  threads: threads,
                                  pattern: job.1,
                                  duration: duration,
                                  isSequential: false)
                let result = DiskIO.measure(fd: fd, fileSize: size, spec: spec, token: token)
                let entry = CustomEntry(title: job.0,
                                        result: result.isUsable ? result : nil,
                                        failure: result.error)
                entries.append(entry)
                event(.finished(entry))
            }
        } catch {
            errorText = error.localizedDescription
            event(.status("出错：\(error.localizedDescription)"))
        }

        var lines = ["fio 存储测试 · 随机读写（iOS / native-posix）"]
        lines.append("块大小 \(blockSize) · QD\(qd) T\(threads) · 每项 \(Int(duration)) 秒 · direct=\(direct ? 1 : 0)")
        for entry in entries {
            if let result = entry.result {
                lines.append(String(format: "%@: 读 %.1f / 写 %.1f MB/s · %.0f IOPS · 延迟 %@",
                                    entry.title, result.readBW, result.writeBW,
                                    result.totalIOPS, formatLatency(result.averageLatencyUS)))
            } else {
                lines.append("\(entry.title): 失败 \(entry.failure ?? "")")
            }
        }
        if let errorText { lines.append("错误: \(errorText)") }

        return CustomOutcome(entries: entries, report: lines.joined(separator: "\n"),
                             error: errorText, stopped: token.isStopped)
    }
}
