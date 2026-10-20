import Foundation
import Darwin

struct StressUpdate {
    var totalBytes: Int64
    var writtenBytes: Int64
    var currentBw: Double
    var averageBw: Double
    var newSample: Double?
}

struct StressOutcome {
    var writtenBytes: Int64
    var elapsed: Double
    var averageBw: Double
    var stopped: Bool
    var error: String?
    var report: String
}

enum StressEngine {
    static func run(totalGB: Int,
                    direct: Bool,
                    token: StopToken,
                    fileURL: URL,
                    update: (StressUpdate) -> Void) -> StressOutcome {
        let totalBytes = Int64(max(1, totalGB)) * 1_073_741_824
        var fd: Int32 = -1
        var errorText: String?
        var written: Int64 = 0
        var currentBw = 0.0
        var samples: [Double] = []
        var stoppedByUser = false

        defer {
            if fd >= 0 { close(fd) }
            try? FileManager.default.removeItem(at: fileURL)
        }

        do {
            fd = try DiskIO.openWritable(url: fileURL, size: totalBytes, direct: direct)
        } catch {
            errorText = error.localizedDescription
            let report = "压力测试失败：\(error.localizedDescription)"
            return StressOutcome(writtenBytes: 0, elapsed: 0, averageBw: 0,
                                 stopped: false, error: errorText, report: report)
        }

        let chunk = 1_048_576
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 4_096)
        defer { buffer.deallocate() }
        memset(buffer, 0x3C, chunk)

        let wallStart = DispatchTime.now().uptimeNanoseconds
        var lastSampleTime = wallStart
        var lastSampleBytes: Int64 = 0
        var offset: Int64 = 0

        update(StressUpdate(totalBytes: totalBytes, writtenBytes: 0,
                            currentBw: 0, averageBw: 0, newSample: nil))

        while offset < totalBytes {
            if token.isStopped {
                stoppedByUser = true
                break
            }

            let count = pwrite(fd, buffer, chunk, off_t(offset))
            let after = DispatchTime.now().uptimeNanoseconds

            if count < 0 {
                if errno == EINTR { continue }
                errorText = String(cString: strerror(errno))
                break
            }
            if count == 0 { break }

            offset += Int64(count)
            written = offset

            let elapsedSinceSample = Double(after - lastSampleTime) / 1_000_000_000.0
            if elapsedSinceSample >= 0.25 {
                currentBw = Double(offset - lastSampleBytes) / 1_048_576.0 / elapsedSinceSample
                samples.append(currentBw)
                if samples.count > 600 { samples.removeFirst(samples.count - 600) }
                let average = Double(offset) / 1_048_576.0 / max(0.001, Double(after - wallStart) / 1_000_000_000.0)
                update(StressUpdate(totalBytes: totalBytes, writtenBytes: offset,
                                    currentBw: currentBw, averageBw: average,
                                    newSample: currentBw))
                lastSampleTime = after
                lastSampleBytes = offset
            }
        }

        let wallEnd = DispatchTime.now().uptimeNanoseconds
        let elapsed = max(0.001, Double(wallEnd - wallStart) / 1_000_000_000.0)
        let average = Double(written) / 1_048_576.0 / elapsed
        if elapsed > 0 && written > 0 {
            currentBw = average
        }
        update(StressUpdate(totalBytes: totalBytes, writtenBytes: written,
                            currentBw: currentBw, averageBw: average, newSample: nil))

        var lines = ["fio 存储测试 · 持续写入（iOS / native-posix）"]
        lines.append("总量 \(totalGB) GB · 1 GB 分块 · direct=\(direct ? 1 : 0)")
        lines.append(String(format: "已写入 %.2f GB · 平均 %.1f MB/s · 用时 %.1f 秒",
                            Double(written) / 1_073_741_824.0, average, elapsed))
        if stoppedByUser { lines.append("用户请求停止，文件已删除") }
        if let errorText { lines.append("错误: \(errorText)") }

        return StressOutcome(writtenBytes: written, elapsed: elapsed, averageBw: average,
                             stopped: stoppedByUser, error: errorText,
                             report: lines.joined(separator: "\n"))
    }
}
