import SwiftUI
import UIKit

struct BenchmarkPage: View {
    @EnvironmentObject private var model: AppModel

    @State private var target: StorageTarget = .builtin
    @State private var gapSeconds = 2
    @State private var fileSizeMB = 512
    @State private var direct = true

    var body: some View {
        PageScroll {
            parameters
            scoreCard
            detailCard
            if !model.diagnostics.isEmpty {
                diagnosticsCard
            }
            historyCard
        }
    }

    private var parameters: some View {
        Card {
            CardTitle(title: "基准测试", subtitle: "14 项 · 每项 8 秒 · 综合几何平均分")
            TargetPicker(target: $target)
            Divider().background(Theme.stroke)
            IntStepperRow(title: "项间间隔", value: $gapSeconds, range: 0...30, suffix: " 秒")
            IntStepperRow(title: "测试文件", value: $fileSizeMB, range: 64...4096, suffix: " MB", step: 64)
            ToggleRow(title: "direct=1", subtitle: "iOS 无 O_DIRECT，映射为 F_NOCACHE", isOn: $direct)
            PrimaryButton(title: model.running ? "测试进行中…" : "开始基准测试",
                          enabled: !model.running) {
                model.startBenchmark(gapSeconds: Double(gapSeconds),
                                     sizeMB: fileSizeMB,
                                     direct: direct)
            }
            SecondaryButton(title: "环境诊断", enabled: !model.running) {
                model.refreshDiagnostics()
            }
            HintText(text: "同一时间只运行一个测试。每次开始前会删除旧文件，结束后再次清理 bench/ 目录。可用空间 \(model.freeSpaceText)。")
        }
    }

    private var scoreCard: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("综合得分")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.sub)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(model.benchScore)
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor)
                        Text("分")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.sub)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("14 项加权")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.sub)
                    Text("参考 UFS 3.x")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.sub)
                    Text("1000 分基准")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.sub)
                }
                .padding(.top, 3)
            }
            Divider().background(Theme.stroke)
            Text("分数 = 1000 × exp(Σ 权重×ln(ratio) / Σ权重)，ratio 下限 0.02。任何一项异常都会拉低总分，顺序快不能掩盖 4K 慢。")
                .font(.system(size: 9))
                .foregroundColor(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scoreColor: Color {
        if model.benchScoreValue >= 1000 { return Theme.green }
        if model.benchScoreValue >= 600 { return Theme.amber }
        if model.benchScoreValue > 0 { return Theme.red }
        return Theme.text
    }

    private var detailCard: some View {
        Card {
            HStack {
                CardTitle(title: "各项明细")
                Spacer()
                if model.running {
                    Text("实时刷新")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.accent)
                }
            }

            VStack(spacing: 0) {
                ForEach(model.benchItems) { item in
                    detailRow(item)
                    if item.id != model.benchItems.count - 1 {
                        Divider().background(Theme.stroke.opacity(0.7))
                    }
                }
            }
        }
    }

    private func detailRow(_ item: BenchItem) -> some View {
        let ratio: Double? = {
            guard let result = item.result, result.isUsable, item.referenceBW > 0 else { return nil }
            return result.totalBW / item.referenceBW
        }()

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: item.state == .running ? .semibold : .regular))
                    .foregroundColor(item.state == .running ? Theme.accent : Theme.text)
                Text("\(item.sub) · 参考 \(Int(item.referenceBW)) MB/s")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.sub)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.benchmarkValue(for: item))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(rowColor(item))
                if let ratio {
                    Text(String(format: "%.0f%%", ratio * 100))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(rowColor(item))
                }
            }
        }
        .padding(.vertical, 7)
        .background(item.state == .running ? Theme.accent.opacity(0.045) : Color.clear)
    }

    private func rowColor(_ item: BenchItem) -> Color {
        if item.state == .failed { return Theme.red }
        if item.state == .running { return Theme.accent }
        guard let result = item.result, result.isUsable, item.referenceBW > 0 else { return Theme.sub }
        let ratio = result.totalBW / item.referenceBW
        if ratio >= 1 { return Theme.green }
        if ratio >= 0.5 { return Theme.amber }
        return Theme.red
    }

    private var diagnosticsCard: some View {
        Card {
            HStack {
                CardTitle(title: "环境诊断")
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = model.diagnostics
                    model.status = "诊断报告已复制"
                }) {
                    Text("复制")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.field)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Text(model.diagnostics)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.sub)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var historyCard: some View {
        Card {
            CardTitle(title: "成绩历史", subtitle: "最近 12 条 · Documents/FioBench/history.txt")
            if model.history.isEmpty {
                EmptyHint(text: "暂无记录")
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.history.indices, id: \.self) { index in
                        Text(model.history[index])
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.sub)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}
