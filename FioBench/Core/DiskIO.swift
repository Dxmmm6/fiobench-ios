import Foundation
import Darwin

enum DiskIO {
    static func checkSpace(for size: Int64) throws {
        let free = EnginePaths.freeBytes()
        if free > 0 && free < size + 64 * 1_048_576 {
            throw DiskError.noSpace(required: size, available: free)
        }
    }

    static func openWritable(url: URL, size: Int64, direct: Bool) throws -> Int32 {
        try checkSpace(for: size)
        EnginePaths.ensureDirectories()
        let fd = open(url.path, O_RDWR | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else {
            throw DiskError.cannotOpen(url.lastPathComponent, String(cString: strerror(errno)))
        }
        if direct {
            _ = fb_set_nocache(fd)
        }
        guard ftruncate(fd, off_t(size)) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw DiskError.io("预分配文件失败：\(reason)")
        }
        return fd
    }

    static func fill(fd: Int32, size: Int64, token: StopToken,
                     progress: ((Double) -> Void)? = nil) throws {
        let chunk = 1_048_576
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 4_096)
        defer { buffer.deallocate() }
        memset(buffer, 0xA5, chunk)

        var offset: Int64 = 0
        while offset < size {
            if token.isStopped { throw DiskError.cancelled }
            let want = Int(min(Int64(chunk), size - offset))
            let written = pwrite(fd, buffer, want, off_t(offset))
            if written < 0 {
                if errno == EINTR { continue }
                throw DiskError.io("写入准备数据失败：\(String(cString: strerror(errno)))")
            }
            if written == 0 { break }
            offset += Int64(written)
            if let progress, offset % (64 * 1_048_576) == 0 {
                progress(Double(offset) / Double(size))
            }
        }
        progress?(1.0)
    }

    static func measure(fd: Int32, fileSize: Int64, spec: IOSpec, token: StopToken) -> IOResult {
        let requestedWorkers = max(1, spec.threads * spec.qd)
        let maximumWorkers = spec.isSequential ? 8 : 32
        let workers = max(1, min(requestedWorkers, maximumWorkers))
        let box = StatsBox()
        let wallStart = DispatchTime.now().uptimeNanoseconds
        let deadline = wallStart &+ UInt64(spec.duration * 1_000_000_000.0)
        let blockSize = max(512, spec.blockSize)
        let pattern = spec.pattern

        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: blockSize, alignment: 4_096)
            defer { buffer.deallocate() }
            memset(buffer, 0xA5, blockSize)

            var readBytes: Int64 = 0
            var writeBytes: Int64 = 0
            var readOps: Int64 = 0
            var writeOps: Int64 = 0
            var readLatency: Double = 0
            var writeLatency: Double = 0

            let perWorker = max(Int64(blockSize), fileSize / Int64(workers))
            var sequentialStart = perWorker * Int64(worker)
            let rawEnd = worker == workers - 1 ? fileSize : min(fileSize, sequentialStart + perWorker)
            sequentialStart -= sequentialStart % Int64(blockSize)
            var sequentialEnd = rawEnd - rawEnd % Int64(blockSize)
            if sequentialEnd <= sequentialStart {
                sequentialEnd = min(fileSize, sequentialStart + Int64(blockSize))
            }
            let regionSize = max(Int64(blockSize), sequentialEnd - sequentialStart)
            var offset = spec.isSequential ? sequentialStart : 0

            while DispatchTime.now().uptimeNanoseconds < deadline && !token.isStopped {
                let isRead: Bool
                switch pattern {
                case .read:
                    isRead = true
                case .write:
                    isRead = false
                case .mixed(let percent):
                    isRead = Int(arc4random_uniform(100)) < percent
                }

                if spec.isSequential {
                    if offset + Int64(blockSize) > sequentialStart + regionSize {
                        offset = sequentialStart
                    }
                } else {
                    offset = randomOffset(fileSize: fileSize, blockSize: blockSize)
                }

                let before = DispatchTime.now().uptimeNanoseconds
                let count: Int
                if isRead {
                    count = pread(fd, buffer, blockSize, off_t(offset))
                } else {
                    count = pwrite(fd, buffer, blockSize, off_t(offset))
                }
                let after = DispatchTime.now().uptimeNanoseconds

                if count < 0 {
                    if errno == EINTR { continue }
                    box.setError(String(cString: strerror(errno)))
                    break
                }
                if count == 0 { break }

                let latency = Double(after - before)
                if isRead {
                    readBytes += Int64(count)
                    readOps += 1
                    readLatency += latency
                } else {
                    writeBytes += Int64(count)
                    writeOps += 1
                    writeLatency += latency
                }

                if spec.isSequential {
                    offset += Int64(blockSize)
                }
            }

            box.add(readBytes: readBytes, writeBytes: writeBytes,
                    readOps: readOps, writeOps: writeOps,
                    readLatencyNS: readLatency, writeLatencyNS: writeLatency)
        }

        let wallEnd = DispatchTime.now().uptimeNanoseconds
        var result = IOResult()
        result.readBytes = box.readBytes
        result.writeBytes = box.writeBytes
        result.readOps = box.readOps
        result.writeOps = box.writeOps
        result.readLatencyNS = box.readLatencyNS
        result.writeLatencyNS = box.writeLatencyNS
        result.elapsed = max(0.001, Double(wallEnd - wallStart) / 1_000_000_000.0)
        result.error = box.firstError
        return result
    }

    static func measureFullFile(fd: Int32, fileSize: Int64, blockSize: Int,
                                isWrite: Bool, token: StopToken,
                                progress: ((Double) -> Void)? = nil) -> IOResult {
        let wallStart = DispatchTime.now().uptimeNanoseconds
        let bs = max(512, blockSize)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bs, alignment: 4_096)
        defer { buffer.deallocate() }
        memset(buffer, 0x5A, bs)

        var result = IOResult()
        var offset: Int64 = 0
        var nextReport: Int64 = 0

        while offset < fileSize {
            if token.isStopped {
                result.error = "已请求停止"
                break
            }
            let want = Int(min(Int64(bs), fileSize - offset))
            let before = DispatchTime.now().uptimeNanoseconds
            let count = isWrite
                ? pwrite(fd, buffer, want, off_t(offset))
                : pread(fd, buffer, want, off_t(offset))
            let after = DispatchTime.now().uptimeNanoseconds

            if count < 0 {
                if errno == EINTR { continue }
                result.error = String(cString: strerror(errno))
                break
            }
            if count == 0 { break }

            offset += Int64(count)
            let latency = Double(after - before)
            if isWrite {
                result.writeBytes += Int64(count)
                result.writeOps += 1
                result.writeLatencyNS += latency
            } else {
                result.readBytes += Int64(count)
                result.readOps += 1
                result.readLatencyNS += latency
            }

            if offset >= nextReport {
                progress?(min(1.0, Double(offset) / Double(fileSize)))
                nextReport = offset + 64 * 1_048_576
            }
        }

        let wallEnd = DispatchTime.now().uptimeNanoseconds
        result.elapsed = max(0.001, Double(wallEnd - wallStart) / 1_000_000_000.0)
        progress?(1.0)
        return result
    }

    private static func randomOffset(fileSize: Int64, blockSize: Int) -> Int64 {
        let blocks = max(1, fileSize / Int64(blockSize))
        let value = (UInt64(arc4random()) << 32) | UInt64(arc4random())
        return Int64(value % UInt64(blocks)) * Int64(blockSize)
    }
}
