import SwiftUI
import Foundation

struct CDMPage: View {
    @EnvironmentObject private var model: AppModel

    @State private var target: StorageTarget = .builtin
    @State private var sizeIndex = 2
    @State private var passesIndex = 0
    @State private var mixIndex = 0
    @State private var direct = true

    private let passOptions = ["1", "3", "5"]

    var body: some View {
        PageScroll {
            parameters
            resultCard
        }
    }

    private var parameters: some View {
        Card {
            CardTitle(title: "CrystalDiskMark  ·  \(model.useIOPS ? "IOPS" : "MB/s")",
                      subtitle: "4 × 3 格 · 每格独立跑 8 秒")
            TargetPicker(target: $target)
            Divider().background(Theme.stroke)
            Text("数据大小")
                .font(.system(size: 12))
                .foregroundColor(Theme.sub)
            Chips(options: CDMCatalog.sizeOptions.map { $0.label }, selected: $sizeIndex, compact: true)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("测试次数")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.sub)
                    Chips(options: passOptions, selected: $passesIndex, compact: true)
                }
                Spacer(minLength: 0)
            }

            Text("混合比例")
                .font(.system(size: 12))
                .foregroundColor(Theme.sub)
            Chips(options: CDMCatalog.mixOptions.map { $0.label }, selected: $mixIndex, compact: true)

            ToggleRow(title: "direct=1", subtitle: "F_NOCACHE；有 root 时 fio 的 drop_caches 在 iOS 不可用", isOn: $direct)
            PrimaryButton(title: model.running ? "测试进行中…" : "开始 CDM 测试",
                          enabled: !model.running) {
                let size = CDMCatalog.sizeOptions[sizeIndex].mb
                let passes = [1, 3, 5][passesIndex]
                let mix = CDMCatalog.mixOptions[mixIndex].readPercent
                model.startCDM(sizeMB: size, passes: passes, mixReadPercent: mix, direct: direct)
            }
            HintText(text: "每格依次执行 Read / Write / Mix，结果实时刷新；结束后自动删除测试文件。")
        }
    }

    private var resultCard: some View {
        Card {
            HStack {
                CardTitle(title: "CrystalDiskMark  ·  \(model.useIOPS ? "IOPS" : "MB/s")")
                Spacer()
                Text("\(CDMCatalog.sizeOptions[sizeIndex].label) · ×\([1, 3, 5][passesIndex])")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.sub)
            }

            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("")
                        .frame(width: 82, alignment: .leading)
                    ForEach(["Read", "Write", "Mix"], id: \.self) { heading in
                        Text(heading)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.sub)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(CDMCatalog.rows) { row in
                    HStack(spacing: 4) {
                        Text(row.title)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.sub)
                            .frame(width: 82, alignment: .leading)
                            .lineLimit(2)
                        ForEach(0..<3, id: \.self) { column in
                            cdmCell(row: row.id, column: column)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            Divider().background(Theme.stroke)
            HintText(text: "R70/W30 等混合比例按操作概率分配。iOS 无 drop_caches；direct=1 使用 F_NOCACHE。")
        }
    }

    private func cdmCell(row: Int, column: Int) -> some View {
        let active = model.cdmActiveRow == row && model.cdmActiveColumn == column
        let value = model.cdmValue(row: row, column: column)
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
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(active ? Theme.accent.opacity(0.10) : Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(active ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }
}
