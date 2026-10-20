import SwiftUI
import Foundation

struct StressPage: View {
    @EnvironmentObject private var model: AppModel

    @State private var totalGB = 10
    @State private var direct = true

    var body: some View {
        PageScroll {
            parameters
            progressCard
        }
    }

    private var parameters: some View {
        Card {
            CardTitle(title: "压力测试", subtitle: "持续顺序写入 · 1 GB 分块 · 实时速度曲线")
            IntStepperRow(title: "写入量", value: $totalGB, range: 1...50, suffix: " GB")
            ToggleRow(title: "direct=1", subtitle: "iOS 映射为 F_NOCACHE", isOn: $direct)
            HStack(spacing: 8) {
                PrimaryButton(title: model.running ? "运行中…" : "开始",
                              enabled: !model.running) {
                    model.startStress(totalGB: totalGB, direct: direct)
                }
                Button(action: { model.stopStress() }) {
                    Text("停止")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(model.running ? Theme.red : Theme.sub.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(model.running ? Theme.red.opacity(0.13) : Theme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(model.running ? Theme.red.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.running)
            }
            HintText(text: "停止会立即中断当前写入并删除测试文件。可用空间 \(model.freeSpaceText)，请确保大于写入量。")
        }
    }

    private var progressCard: some View {
        Card {
            HStack(alignment: .lastTextBaseline) {
                Text("\(Int((model.stress.fraction * 100).rounded()))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("已写入")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.sub)
                    Text(String(format: "%.2f GB / %.0f GB",
                                Double(model.stress.writtenBytes) / 1_073_741_824.0,
                                Double(max(model.stress.totalBytes, Int64(totalGB) * 1_073_741_824)) / 1_073_741_824.0))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.text)
                }
            }

            ProgressView(value: model.stress.fraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)
                .padding(.vertical, 4)

            HStack(spacing: 8) {
                metric(title: "当前", value: formatBandwidth(model.stress.currentBw), color: Theme.accent)
                metric(title: "平均", value: formatBandwidth(model.stress.averageBw), color: Theme.green)
                metric(title: "已写入", value: formatBytes(model.stress.writtenBytes), color: Theme.text)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("实时速度")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.sub)
                    Spacer()
                    Text("200dp · \(model.stress.samples.count) 采样")
                        .font(.system(size: 8))
                        .foregroundColor(Theme.sub.opacity(0.8))
                }
                SpeedChart(samples: model.stress.samples)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            }
        }
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(Theme.sub)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SpeedChart: View {
    let samples: [Double]

    var body: some View {
        Canvas { context, size in
            let maxValue = max(samples.max() ?? 1, 1)
            let insets = EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
            let plot = CGRect(x: insets.leading,
                              y: insets.top,
                              width: max(1, size.width - insets.leading - insets.trailing),
                              height: max(1, size.height - insets.top - insets.bottom))

            for line in 0...4 {
                let y = plot.minY + plot.height * CGFloat(line) / 4.0
                var grid = Path()
                grid.move(to: CGPoint(x: plot.minX, y: y))
                grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(grid, with: .color(Theme.stroke), lineWidth: 0.7)
            }

            guard samples.count >= 2 else {
                return
            }

            var path = Path()
            for (index, value) in samples.enumerated() {
                let x = plot.minX + plot.width * CGFloat(index) / CGFloat(max(1, samples.count - 1))
                let normalized = CGFloat(max(0, min(1, value / maxValue)))
                let y = plot.maxY - plot.height * normalized
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            var fill = path
            fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [Theme.accent.opacity(0.26), Theme.accent.opacity(0.01)]),
                startPoint: CGPoint(x: 0, y: plot.minY),
                endPoint: CGPoint(x: 0, y: plot.maxY)
            ))
            context.stroke(path, with: .color(Theme.accent), lineWidth: 1.6)
        }
        .background(Theme.field.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Text(formatBandwidth(max(samples.max() ?? 0, 1)))
                .font(.system(size: 8, design: .rounded))
                .foregroundColor(Theme.sub)
                .padding(.leading, 8)
                .padding(.top, 6)
        }
        .overlay {
            if samples.count < 2 {
                Text("等待采样…")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.sub.opacity(0.6))
            }
        }
    }
}
