import Foundation
import Darwin

enum RawEvent {
    case status(String)
    case started(Int)
    case finished(Int, IOResult)
}

struct RawOutcome {
    var results: [IOResult?]
    var report: String
    var error: String?
}

enum RawEngine {
    static func probe() -> RawProbe {
        let root = fb_is_jailbroken() != 0
        let candidates = [
            "/dev/disk0",
            "/dev/rdisk0",
            "/dev/block/by-name/userdata",
            "/dev/block/bootdevice/by-name/userdata"
        ]

        for path in candidates {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                let size = fb_disk_size(fd)
                close(fd)
                if size > 0 {
                    return RawProbe(path: path, capacity: Int64(size), isRoot: root,
                                    message: root ? "块设备可读" : "设备节点可打开，但 iOS 沙箱可能仍拒绝读取")
                }
            }
        }

        return RawProbe(path: nil, capacity: 0, isRoot: root,
                        message: root ? "未找到可读块设备" : "裸设备测试需要 root / 越狱")
    }

    static func run(devicePath: String,
                    capacity: Int64,
                    direct: Bool,
                    token: StopToken,
                    event: (RawEvent) -> Void) -> RawOutcome {
        var results = [IOResult?](repeating: nil, count: 3)
        let fd = open(devicePath, O_RDONLY)
        var errorText: String?

        if fd < 0 {
            errorText = "无法以只读方式打开 \(devicePath)：\(String(cString: strerror(errno)))"
            event(.status("裸读失败：\(errorText ?? "")"))
            return RawOutcome(results: results,
                              report: "裸读失败：\(errorText ?? "未知错误")",
                              error: errorText)
        }

        defer { close(fd) }
        if direct { _ = fb_set_nocache(fd) }

        let capacityMB = capacity / 1_048_576
        let wantedMB = min(512, max(64, capacityMB / 4))
        let region = max(4_096, min(capacity, wantedMB * 1_048_576))

        let jobs: [(String, Int, Int, Bool)] = [
            ("顺序读 1M QD32", 1 << 20, 32, true),
            ("随机读 4K QD32", 4096, 32, false),
            ("随机读 4K QD1", 4096, 1, false)
        ]

        event(.status("裸读准备完毕 · \(formatBytes(region)) 测试区"))
        for (index, job) in jobs.enumerated() {
            if token.isStopped { break }
            event(.status("裸读 \(index + 1)/3 · \(job.0)"))
            event(.started(index))
            let spec = IOSpec(name: job.0, blockSize: job.1, qd: job.2, threads: 1,
                              pattern: .read, duration: 8, isSequential: job.3)
            let result = DiskIO.measure(fd: fd, fileSize: region, spec: spec, token: token)
            results[index] = result
            event(.finished(index, result))
        }

        var lines = ["fio 存储测试 · 裸读（iOS / native-posix）"]
        lines.append("设备 \(devicePath) · 容量 \(formatBytes(capacity)) · 测试区 \(formatBytes(region))")
        lines.append("只读 · direct=\(direct ? 1 : 0) · 每项 8 秒")
        for (index, job) in jobs.enumerated() {
            if let result = results[index] {
                lines.append(String(format: "%@: %.1f MB/s · %.0f IOPS",
                                    job.0, result.readBW, result.readIOPS))
            }
        }
        let anySuccess = results.contains { result in
            if let result = result { return result.isUsable }
            return false
        }
        if errorText == nil && !anySuccess {
            errorText = "块设备读取被拒绝（iOS 沙箱/权限限制）"
        }
        if let errorText { lines.append("错误: \(errorText)") }

        return RawOutcome(results: results, report: lines.joined(separator: "\n"), error: errorText)
    }
}
