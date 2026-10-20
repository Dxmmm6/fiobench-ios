import SwiftUI
import Foundation

struct ASSSDPage: View {
    @EnvironmentObject private var model: AppModel

    @State private var target: StorageTarget = .builtin
    @State private var direct = true

    private let rows: [(title: String, readIndex: Int, writeIndex: Int)] = [
        ("Seq 1M QD32", 0, 1),
        ("4K QD1", 2, 3),
        ("4K-64Thrd", 4, 5)
    ]

    var body: some View {
        PageScroll {
            parameters
            resultCard
            scoreCard
        }
    }

    private var parameters: some View {
        Card {
            CardTitle(title: "AS SSD", subtitle: "固定 1024 MB · 每项 8 秒 · 重随机轻顺序")
            TargetPicker(target: $target)
            ToggleRow(title: "direct=1", subtitle: "iOS 映射为 F_NOCACHE", isOn: $direct)
            PrimaryButton(title: model.running ? "测试进行中…" : "开始 AS SSD",
                          enabled: !model.running) {
                model.startASSSD(direct: direct)
            }
            HintText(text: "顺序 QD32 → 4K QD1 → 4K-64Thrd。访问时间取 4K QD1 的平均延迟。")
        }
    }

    private var resultCard: some View {
        Card {
            CardTitle(title: "AS SSD  ·  \(model.useIOPS ? "IOPS" : "MB/s")")
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("")
                        .frame(width: 92, alignment: .leading)
                    ForEach(["Read", "Write"], id: \.self) { heading in
                        Text(heading)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.sub)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(rows.indices, id: \.self) { rowIndex in
                    let row = rows[rowIndex]
                    HStack(spacing: 4) {
                        Text(row.title)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.sub)
                            .frame(width: 92, alignment: .leading)
                        cell(index: row.readIndex)
                        cell(index: row.writeIndex)
                    }
                }

                HStack(spacing: 4) {
                    Text("访问时间")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.sub)
                        .frame(width: 92, alignment: .leading)
                    latencyCell(model.assdAccessTimeRead, active: model.assdRunningIndex == 2)
                    latencyCell(model.assdAccessTimeWrite, active: model.assdRunningIndex == 3)
                }
            }
            HintText(text: "访问时间显示 4K QD1 的平均延迟；μs/ms 自动切换。")
        }
    }

    private func cell(index: Int) -> some View {
        let active = model.assdRunningIndex == index
        let value = model.assdValue(index: index)
        return VStack(spacing: 1) {
            Text(active ? "…" : value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(active ? Theme.accent : (value == "失败" ? Theme.red : Theme.text))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(model.useIOPS ? "IOPS" : "MB/s")
                .font(.system(size: 7))
                .foregroundColor(Theme.sub.opacity(0.75))
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(active ? Theme.accent.opacity(0.10) : Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(active ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }

    private func latencyCell(_ value: String, active: Bool) -> some View {
        VStack(spacing: 1) {
            Text(active ? "…" : value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(active ? Theme.accent : Theme.text)
            Text("avg")
                .font(.system(size: 7))
                .foregroundColor(Theme.sub.opacity(0.75))
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(active ? Theme.accent.opacity(0.10) : Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var scoreCard: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("总分")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.sub)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(model.assdTotalScore > 0 ? String(format: "%.0f", model.assdTotalScore) : "--")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor)
                        Text("分")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.sub)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    LabeledValue(label: "读分", value: model.assdReadScore > 0 ? String(format: "%.0f", model.assdReadScore) : "--")
                    LabeledValue(label: "写分", value: model.assdWriteScore > 0 ? String(format: "%.0f", model.assdWriteScore) : "--")
                }
            }
            Divider().background(Theme.stroke)
            Text("读分 = 0.2×顺序 + 8.0×4K + 0.8×4K-64Thrd；写分 = 0.2×顺序 + 12.0×4K + 0.8×4K-64Thrd。这是项目自建公式，不是 AS SSD 官方分。")
                .font(.system(size: 9))
                .foregroundColor(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scoreColor: Color {
        if model.assdTotalScore >= 4000 { return Theme.green }
        if model.assdTotalScore >= 2000 { return Theme.amber }
        if model.assdTotalScore > 0 { return Theme.red }
        return Theme.text
    }
}
