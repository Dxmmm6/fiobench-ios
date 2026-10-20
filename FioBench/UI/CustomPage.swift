import SwiftUI
import Foundation

struct CustomPage: View {
    @EnvironmentObject private var model: AppModel

    @State private var target: StorageTarget = .builtin
    @State private var direct = true

    @State private var seqBlockIndex = 1
    @State private var seqFileMB = 1024

    @State private var randBlockIndex = 0
    @State private var qd = 32
    @State private var threads = 1
    @State private var duration = 20

    private let seqBlocks: [(label: String, bytes: Int)] = [
        ("512K", 512 * 1024),
        ("1M", 1 << 20),
        ("2M", 2 << 20),
        ("4M", 4 << 20)
    ]
    private let randomBlocks: [(label: String, bytes: Int)] = [
        ("4K", 4096),
        ("8K", 8192),
        ("16K", 16384),
        ("64K", 65536)
    ]

    var body: some View {
        PageScroll {
            sharedCard
            sequentialCard
            randomCard
            resultsCard
        }
    }

    private var sharedCard: some View {
        Card {
            CardTitle(title: "自定义测试", subtitle: "顺序与随机分开设置、分开运行")
            TargetPicker(target: $target)
            ToggleRow(title: "direct=1", subtitle: "iOS 映射为 F_NOCACHE", isOn: $direct)
        }
    }

    private var sequentialCard: some View {
        Card {
            CardTitle(title: "顺序读写", subtitle: "先写后读，关闭 time_based，跑完整个文件")
            Text("块大小")
                .font(.system(size: 12))
                .foregroundColor(Theme.sub)
            Chips(options: seqBlocks.map { $0.label }, selected: $seqBlockIndex, compact: true)
            IntStepperRow(title: "文件大小", value: $seqFileMB, range: 64...4096, suffix: " MB", step: 64)
            PrimaryButton(title: model.running ? "测试进行中…" : "只跑顺序测试",
                          enabled: !model.running) {
                model.startCustomSequential(blockSize: seqBlocks[seqBlockIndex].bytes,
                                            fileMB: seqFileMB,
                                            direct: direct)
            }
            HintText(text: "结果是大文件持续传输速度，不受固定时长截断。")
        }
    }

    private var randomCard: some View {
        Card {
            CardTitle(title: "随机读写", subtitle: "随机写 → 随机读 → 混合 70/30，每项固定时长")
            Text("块大小")
                .font(.system(size: 12))
                .foregroundColor(Theme.sub)
            Chips(options: randomBlocks.map { $0.label }, selected: $randBlockIndex, compact: true)
            IntStepperRow(title: "队列深度 QD", value: $qd, range: 1...64)
            IntStepperRow(title: "线程数 T", value: $threads, range: 1...8)
            IntStepperRow(title: "每项时长", value: $duration, range: 5...120, suffix: " 秒", step: 5)
            PrimaryButton(title: model.running ? "测试进行中…" : "只跑随机测试",
                          enabled: !model.running) {
                model.startCustomRandom(blockSize: randomBlocks[randBlockIndex].bytes,
                                        qd: qd,
                                        threads: threads,
                                        duration: Double(duration),
                                        direct: direct)
            }
            HintText(text: "随机测试使用固定 1024 MB 文件；每项显示带宽、IOPS 和平均延迟。")
        }
    }

    private var resultsCard: some View {
        Card {
            CardTitle(title: "结果")
            if model.customEntries.isEmpty {
                EmptyHint(text: "运行任一测试后，结果会实时出现在这里")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.customEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.text)
                            if let result = entry.result {
                                if result.readBytes > 0 {
                                    customLine("读", result.readBW, result.readIOPS, result.readLatencyUS)
                                }
                                if result.writeBytes > 0 {
                                    customLine("写", result.writeBW, result.writeIOPS, result.writeLatencyUS)
                                }
                            } else {
                                Text(entry.failure ?? "失败")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.red)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider().background(Theme.stroke.opacity(0.7))
                    }
                }
            }
        }
    }

    private func customLine(_ prefix: String, _ bw: Double, _ iops: Double, _ latencyUS: Double) -> some View {
        Text("\(prefix): \(formatBandwidth(bw))   \(formatIOPS(iops))   延迟 \(formatLatency(latencyUS))")
            .font(.system(size: 10, design: .rounded))
            .foregroundColor(Theme.sub)
    }
}
