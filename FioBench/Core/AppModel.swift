import Foundation
import UIKit
import Combine
import Darwin

final class AppModel: ObservableObject {
    // Global frame
    @Published var tab: AppTab = .bench
    @Published var useIOPS = false
    @Published var running = false
    @Published var status = "就绪"
    @Published var deviceModel = "iPhone"
    @Published var osVersion = "iOS"
    @Published var abi = "arm64"
    @Published var engineName = "native-posix"
    @Published var isRoot = false
    @Published var freeSpaceText = "--"
    @Published var history: [String] = []

    // Benchmark
    @Published var benchItems = BenchCatalog.initialItems
    @Published var benchScore = "--"
    @Published var benchScoreValue: Double = 0
    @Published var benchRunningIndex: Int?
    @Published var diagnostics = ""

    // CDM
    @Published var cdmResults = [[IOResult?]](repeating: [IOResult?](repeating: nil, count: 3), count: 4)
    @Published var cdmActiveRow = -1
    @Published var cdmActiveColumn = -1

    // AS SSD
    @Published var assdResults = [IOResult?](repeating: nil, count: 6)
    @Published var assdRunningIndex: Int?
    @Published var assdReadScore: Double = 0
    @Published var assdWriteScore: Double = 0
    @Published var assdTotalScore: Double = 0

    // Custom
    @Published var customEntries: [CustomEntry] = []

    // Stress
    @Published var stress = StressSnapshot()

    // Raw
    @Published var rawProbe = RawProbe(path: nil, capacity: 0, isRoot: false, message: "尚未探测")
    @Published var rawResults = [IOResult?](repeating: nil, count: 3)

    private var didSetup = false
    private var activeToken: StopToken?

    // MARK: - Lifecycle

    func bootstrap() {
        guard !didSetup else { return }
        didSetup = true

        EnginePaths.ensureDirectories()
        EnginePaths.clearBenchDirectory()

        deviceModel = hardwareModel()
        osVersion = "iOS \(UIDevice.current.systemVersion)"
        abi = "arm64"
        isRoot = fb_is_jailbroken() != 0
        refreshHistory()
        refreshFreeSpace()
        rawProbe = RawEngine.probe()
    }

    // MARK: - Display helpers

    func displayValue(bw: Double, iops: Double) -> String {
        useIOPS ? formatIOPS(iops) : formatBandwidth(bw)
    }

    func benchmarkValue(for item: BenchItem) -> String {
        if let result = item.result, result.isUsable {
            return displayValue(bw: result.totalBW, iops: result.totalIOPS)
        }
        switch item.state {
        case .running: return "测试中…"
        case .failed: return "失败"
        default: return "--"
        }
    }

    func cdmValue(row: Int, column: Int) -> String {
        guard row >= 0, row < cdmResults.count,
              column >= 0, column < cdmResults[row].count,
              let result = cdmResults[row][column] else { return "--" }
        guard result.isUsable else { return "失败" }
        switch column {
        case 0:
            return displayValue(bw: result.readBW, iops: result.readIOPS)
        case 1:
            return displayValue(bw: result.writeBW, iops: result.writeIOPS)
        default:
            return displayValue(bw: result.totalBW, iops: result.totalIOPS)
        }
    }

    func assdValue(index: Int) -> String {
        guard index >= 0, index < assdResults.count, let result = assdResults[index] else { return "--" }
        guard result.isUsable else { return "失败" }
        let isRead = index % 2 == 0
        return displayValue(bw: isRead ? result.readBW : result.writeBW,
                            iops: isRead ? result.readIOPS : result.writeIOPS)
    }

    var assdAccessTimeRead: String {
        guard assdResults.count > 2, let result = assdResults[2] else { return "--" }
        return formatLatency(result.averageLatencyUS)
    }

    var assdAccessTimeWrite: String {
        guard assdResults.count > 3, let result = assdResults[3] else { return "--" }
        return formatLatency(result.averageLatencyUS)
    }

    // MARK: - Benchmark

    func startBenchmark(gapSeconds: Double, sizeMB: Int, direct: Bool) {
        guard !running else { return }
        let fileURL = EnginePaths.newTestFile(prefix: "bench")
        benchItems = BenchCatalog.initialItems
        benchScore = "--"
        benchScoreValue = 0
        benchRunningIndex = nil
        begin("基准测试")
        let token = StopToken()
        activeToken = token

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = BenchmarkEngine.run(sizeMB: sizeMB,
                                              direct: direct,
                                              gapSeconds: gapSeconds,
                                              token: token,
                                              fileURL: fileURL) { event in
                DispatchQueue.main.async {
                    switch event {
                    case .status(let text):
                        self.status = text
                    case .started(let index):
                        self.benchRunningIndex = index
                        if index < self.benchItems.count {
                            self.benchItems[index].state = .running
                        }
                    case .finished(let index, let result):
                        if index < self.benchItems.count {
                            self.benchItems[index].result = result
                            self.benchItems[index].state = result.isUsable ? .ok : .failed
                        }
                        self.benchRunningIndex = nil
                    }
                }
            }
            DispatchQueue.main.async {
                self.applyBenchmarkOutcome(outcome, sizeMB: sizeMB, direct: direct)
            }
        }
    }

    private func applyBenchmarkOutcome(_ outcome: BenchOutcome, sizeMB: Int, direct: Bool) {
        for (index, result) in outcome.results.enumerated() where index < benchItems.count {
            benchItems[index].result = result
            benchItems[index].state = (result?.isUsable == true) ? .ok : .failed
        }
        benchScoreValue = outcome.score
        benchScore = outcome.score > 0 ? String(format: "%.0f", outcome.score) : "--"
        benchRunningIndex = nil
        if let error = outcome.error {
            status = "基准出错：\(error)"
        } else if outcome.stopped {
            status = "已请求停止"
        } else {
            status = "基准完成 · 得分 \(benchScore) · 引擎 \(engineName)"
        }

        let summary = String(format: "基准 得分 %@, 引擎 %@, 文件 %dMB, direct=%d",
                             benchScore, engineName, sizeMB, direct ? 1 : 0)
        EnginePaths.record(summary: summary, detail: outcome.report)
        refreshHistory()
        finish()
    }

    // MARK: - CrystalDiskMark

    func startCDM(sizeMB: Int, passes: Int, mixReadPercent: Int, direct: Bool) {
        guard !running else { return }
        let fileURL = EnginePaths.newTestFile(prefix: "cdm")
        cdmResults = [[IOResult?]](repeating: [IOResult?](repeating: nil, count: 3), count: 4)
        cdmActiveRow = -1
        cdmActiveColumn = -1
        begin("CrystalDiskMark")
        let token = StopToken()
        activeToken = token

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = CDMEngine.run(sizeMB: sizeMB,
                                        passes: passes,
                                        mixReadPercent: mixReadPercent,
                                        direct: direct,
                                        token: token,
                                        fileURL: fileURL) { event in
                DispatchQueue.main.async {
                    switch event {
                    case .status(let text):
                        self.status = text
                    case .started(let row, let column):
                        self.cdmActiveRow = row
                        self.cdmActiveColumn = column
                    case .finished(let row, let column, let result):
                        if row < self.cdmResults.count {
                            var rowValues = self.cdmResults[row]
                            rowValues[column] = result
                            self.cdmResults[row] = rowValues
                        }
                        self.cdmActiveRow = -1
                        self.cdmActiveColumn = -1
                    }
                }
            }
            DispatchQueue.main.async {
                self.cdmResults = outcome.results
                self.cdmActiveRow = -1
                self.cdmActiveColumn = -1
                if let error = outcome.error {
                    self.status = "CDM 出错：\(error)"
                } else if outcome.stopped {
                    self.status = "已请求停止"
                } else {
                    self.status = "CDM 完成 · 引擎 \(self.engineName)"
                }
                let summary = "CDM \(sizeMB)MiB ×\(passes) · 引擎 \(self.engineName)"
                EnginePaths.record(summary: summary, detail: outcome.report)
                self.refreshHistory()
                self.finish()
            }
        }
    }

    // MARK: - AS SSD

    func startASSSD(direct: Bool) {
        guard !running else { return }
        let fileURL = EnginePaths.newTestFile(prefix: "asssd")
        assdResults = [IOResult?](repeating: nil, count: 6)
        assdRunningIndex = nil
        assdReadScore = 0
        assdWriteScore = 0
        assdTotalScore = 0
        begin("AS SSD")
        let token = StopToken()
        activeToken = token

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = ASSSDEngine.run(direct: direct, token: token,
                                          fileURL: fileURL) { event in
                DispatchQueue.main.async {
                    switch event {
                    case .status(let text):
                        self.status = text
                    case .started(let index):
                        self.assdRunningIndex = index
                    case .finished(let index, let result):
                        if index < self.assdResults.count {
                            self.assdResults[index] = result
                        }
                        self.assdRunningIndex = nil
                    }
                }
            }
            DispatchQueue.main.async {
                self.assdResults = outcome.results
                self.assdReadScore = outcome.readScore
                self.assdWriteScore = outcome.writeScore
                self.assdTotalScore = outcome.totalScore
                self.assdRunningIndex = nil
                if let error = outcome.error {
                    self.status = "AS SSD 出错：\(error)"
                } else if outcome.stopped {
                    self.status = "已请求停止"
                } else {
                    self.status = String(format: "AS SSD 完成 · 总分 %.0f", outcome.totalScore)
                }
                let summary = String(format: "AS SSD 总分 %.0f · 引擎 %@ direct=%d",
                                     outcome.totalScore, self.engineName, direct ? 1 : 0)
                EnginePaths.record(summary: summary, detail: outcome.report)
                self.refreshHistory()
                self.finish()
            }
        }
    }

    // MARK: - Custom

    func startCustomSequential(blockSize: Int, fileMB: Int, direct: Bool) {
        guard !running else { return }
        let fileURL = EnginePaths.newTestFile(prefix: "seq")
        customEntries = []
        begin("顺序测试")
        let token = StopToken()
        activeToken = token

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = CustomEngine.runSequential(blockSize: blockSize,
                                                      fileMB: fileMB,
                                                      direct: direct,
                                                      token: token,
                                                      fileURL: fileURL) { event in
                DispatchQueue.main.async {
                    switch event {
                    case .status(let text):
                        self.status = text
                    case .progress(_):
                        break
                    case .finished(let entry):
                        self.customEntries.append(entry)
                    }
                }
            }
            DispatchQueue.main.async {
                self.customEntries = outcome.entries
                if let error = outcome.error {
                    self.status = "顺序测试出错：\(error)"
                } else if outcome.stopped {
                    self.status = "已请求停止"
                } else {
                    self.status = "顺序测试完成 · 引擎 \(self.engineName)"
                }
                let summary = "顺序 \(blockSize / 1024)K 文件\(fileMB)MB · 引擎 \(self.engineName)"
                EnginePaths.record(summary: summary, detail: outcome.report)
                self.refreshHistory()
                self.finish()
            }
        }
    }

    func startCustomRandom(blockSize: Int, qd: Int, threads: Int,
                           duration: Double, direct: Bool) {
        guard !running else { return }
        let fileURL = EnginePaths.newTestFile(prefix: "rand")
        customEntries = []
        begin("随机测试")
        let token = StopToken()
        activeToken = token

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = CustomEngine.runRandom(blockSize: blockSize,
                                                 qd: qd,
                                                 threads: threads,
                                                 duration: duration,
                                                 direct: direct,
                                                 token: token,
                                                 fileURL: fileURL) { event in
                DispatchQueue.main.async {
                    switch event {
                    case .status(let text):
                        self.status = text
                    case .progress(_):
                        break
                    case .finished(let entry):
                        self.customEntries.append(entry)
                    }
                }
            }
            DispatchQueue.main.async {
                self.customEntries = outcome.entries
                if let error = outcome.error {
                    self.status = "随机测试出错：\(error)"
                } else if outcome.stopped {
                    self.status = "已请求停止"
                } else {
                    self.status = "随机测试完成 · 引擎 \(self.engineName)"
                }
                let summary = "随机 \(blockSize) QD\(qd) T\(threads) · 引擎 \(self.engineName)"
                EnginePaths.record(summary: summary, detail: outcome.report)
                self.refreshHistory()
                self.finish()
            }
        }
    }

    // MARK: - Stress

    func startStress(totalGB: Int, direct: Bool) {
        guard !running else { return }
        let fileURL = EnginePaths.newTestFile(prefix: "stress")
        stress = StressSnapshot()
        stress.totalBytes = Int64(max(1, totalGB)) * 1_073_741_824
        stress.isRunning = true
        begin("压力测试")
        let token = StopToken()
        activeToken = token

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = StressEngine.run(totalGB: totalGB,
                                           direct: direct,
                                           token: token,
                                           fileURL: fileURL) { update in
                DispatchQueue.main.async {
                    self.stress.totalBytes = update.totalBytes
                    self.stress.writtenBytes = update.writtenBytes
                    self.stress.currentBw = update.currentBw
                    self.stress.averageBw = update.averageBw
                    if let sample = update.newSample {
                        self.stress.samples.append(sample)
                        if self.stress.samples.count > 600 {
                            self.stress.samples.removeFirst(self.stress.samples.count - 600)
                        }
                    }
                    self.status = String(format: "压力 · 已写入 %.2f GB · %.1f MB/s",
                                         Double(update.writtenBytes) / 1_073_741_824.0,
                                         update.averageBw)
                }
            }
            DispatchQueue.main.async {
                self.stress.writtenBytes = outcome.writtenBytes
                self.stress.currentBw = outcome.averageBw
                self.stress.averageBw = outcome.averageBw
                self.stress.isRunning = false
                if let error = outcome.error {
                    self.status = "压力测试出错：\(error)"
                } else if outcome.stopped {
                    self.status = "压力测试已停止 · 文件已删除"
                } else {
                    self.status = String(format: "压力完成 · 平均 %.1f MB/s", outcome.averageBw)
                }
                let summary = String(format: "压力 %dGB 平均 %.1f MB/s · 引擎 %@",
                                     totalGB, outcome.averageBw, self.engineName)
                EnginePaths.record(summary: summary, detail: outcome.report)
                self.refreshHistory()
                self.finish()
            }
        }
    }

    func stopStress() {
        guard running else { return }
        status = "已请求停止"
        activeToken?.stop()
    }

    // MARK: - Raw device

    func refreshRawProbe() {
        rawProbe = RawEngine.probe()
    }

    func startRaw(direct: Bool) {
        guard !running else { return }
        if !rawProbe.isAvailable {
            refreshRawProbe()
        }
        guard let path = rawProbe.path, rawProbe.capacity > 0 else {
            status = "裸设备测试需要 root / 越狱"
            return
        }
        let capacity = rawProbe.capacity

        begin("裸读测试")
        let token = StopToken()
        activeToken = token
        rawResults = [IOResult?](repeating: nil, count: 3)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = RawEngine.run(devicePath: path,
                                        capacity: capacity,
                                        direct: direct,
                                        token: token) { event in
                DispatchQueue.main.async {
                    switch event {
                    case .status(let text):
                        self.status = text
                    case .started(_):
                        break
                    case .finished(let index, let result):
                        if index < self.rawResults.count {
                            self.rawResults[index] = result
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                self.rawResults = outcome.results
                if let error = outcome.error {
                    self.status = "裸读失败：\(error)"
                } else {
                    self.status = "裸读完成 · 引擎 \(self.engineName)"
                }
                let summary = "裸读 \(path) · 引擎 \(self.engineName)"
                EnginePaths.record(summary: summary, detail: outcome.report)
                self.refreshHistory()
                self.finish()
            }
        }
    }

    // MARK: - Diagnostics

    func refreshDiagnostics() {
        status = "诊断中…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let probeURL = EnginePaths.base.appendingPathComponent(".write_probe")
            var writable = "否"
            do {
                try Data("fio".utf8).write(to: probeURL)
                writable = "是"
                try? fm.removeItem(at: probeURL)
            } catch {
                writable = "否（\(error.localizedDescription)）"
            }

            let attrs = try? fm.attributesOfItem(atPath: EnginePaths.base.path)
            let created: String
            if let date = attrs?[FileAttributeKey.creationDate] as? Date {
                created = ISO8601DateFormatter().string(from: date)
            } else {
                created = "--"
            }
            let available = formatBytes(EnginePaths.freeBytes())
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            let listing = EnginePaths.directoryListing()

            var report = "===== 环境诊断 =====\n"
            report += "时间: \(ISO8601DateFormatter().string(from: Date()))\n"
            report += "应用: com.fiobench \(version) (\(build))\n"
            report += "设备: \(self.deviceModel)\n"
            report += "系统: \(self.osVersion) · \(self.abi)\n"
            report += "root/越狱: \(self.isRoot ? "是" : "否")（TrollStore 本身不算越狱）\n"
            report += "引擎: \(self.engineName) · F_NOCACHE\n"
            report += "O_DIRECT: iOS 不支持，direct=1 映射为 F_NOCACHE\n"
            report += "测试目录: \(EnginePaths.bench.path)\n"
            report += "目录创建: \(created)\n"
            report += "目录可写: \(writable)\n"
            report += "可用空间: \(available)\n"
            report += "报告目录: \(EnginePaths.base.path)\n"
            report += "历史文件: \(FileManager.default.fileExists(atPath: EnginePaths.history.path) ? "存在" : "不存在")\n"
            report += "bench/ 内容:\n\(listing)\n"
            report += "fio 二进制: 未嵌入。iOS 沙盒禁止 fork/exec，测试参数在进程内由 native-posix 引擎实现。\n"
            report += "文件共享: 已开启（Files/iTunes）\n"

            DispatchQueue.main.async {
                self.diagnostics = report
                self.status = "诊断完成"
                self.refreshFreeSpace()
            }
        }
    }

    // MARK: - Private helpers

    private func begin(_ message: String) {
        running = true
        status = message
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func finish() {
        running = false
        activeToken = nil
        UIApplication.shared.isIdleTimerDisabled = false
        refreshFreeSpace()
    }

    private func refreshHistory() {
        history = EnginePaths.loadHistory(limit: 12)
    }

    private func refreshFreeSpace() {
        freeSpaceText = formatBytes(EnginePaths.freeBytes())
    }

    private func hardwareModel() -> String {
        var machine = [CChar](repeating: 0, count: 128)
        var size = machine.count
        let result = machine.withUnsafeMutableBytes { buffer -> Int32 in
            sysctlbyname("hw.machine", buffer.baseAddress, &size, nil, 0)
        }
        if result == 0 {
            return "Apple \(String(cString: machine))"
        }
        return UIDevice.current.model
    }
}
