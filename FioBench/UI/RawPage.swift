import SwiftUI
import Foundation

struct RawPage: View {
    @EnvironmentObject private var model: AppModel

    @State private var direct = true

    private let jobs = ["顺序读 1M QD32", "随机读 4K QD32", "随机读 4K QD1"]

    var body: some View {
        PageScroll {
            deviceCard
            resultsCard
        }
        .onAppear {
            if !model.running {
                model.refreshRawProbe()
            }
        }
    }

    private var deviceCard: some View {
        Card {
            CardTitle(title: "裸读", subtitle: "只读，不写任何字节 · 需要 root / 越狱")
            HStack(spacing: 8) {
                Circle()
                    .fill(model.rawProbe.isAvailable ? Theme.green : Theme.red)
                    .frame(width: 6, height: 6)
                Text(model.rawProbe.isAvailable ? "设备可读" : "设备不可用")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(model.rawProbe.isAvailable ? Theme.green : Theme.red)
                Spacer()
                Text(model.rawProbe.isRoot ? "root 已检测" : "无 root")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.sub)
            }

            KeyValueLine(key: "设备路径", value: model.rawProbe.path ?? "--", color: Theme.text)
            KeyValueLine(key: "总容量", value: model.rawProbe.capacity > 0 ? formatBytes(model.rawProbe.capacity) : "--")
            KeyValueLine(key: "状态", value: model.rawProbe.message, color: model.rawProbe.isAvailable ? Theme.green : Theme.sub)
            ToggleRow(title: "direct=1", subtitle: "只读打开，F_NOCACHE", isOn: $direct)

            HStack(spacing: 8) {
                SecondaryButton(title: "重新探测", enabled: !model.running) {
                    model.refreshRawProbe()
                }
                PrimaryButton(title: model.running ? "运行中…" : "开始裸读",
                              enabled: !model.running && model.rawProbe.isAvailable) {
                    model.startRaw(direct: direct)
                }
            }

            HintText(text: "iOS 没有 /dev/block/by-name/userdata。会依次尝试 /dev/disk0、/dev/rdisk0 和 Android 兼容路径；普通沙盒设备通常全部拒绝，只有越狱环境才可能可读。测试区取 min(512, max(64, 容量/4)) MB。")
        }
    }

    private var resultsCard: some View {
        Card {
            CardTitle(title: "裸读结果  ·  \(model.useIOPS ? "IOPS" : "MB/s")")
            VStack(spacing: 0) {
                ForEach(jobs.indices, id: \.self) { index in
                    HStack {
                        Text(jobs[index])
                            .font(.system(size: 11))
                            .foregroundColor(Theme.text)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let result = model.rawResults[index], result.isUsable {
                                Text(model.displayValue(bw: result.readBW, iops: result.readIOPS))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.text)
                                Text("延迟 \(formatLatency(result.averageLatencyUS))")
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.sub)
                            } else if model.rawResults[index] != nil {
                                Text("失败")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.red)
                            } else {
                                Text("--")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(Theme.sub)
                            }
                        }
                    }
                    .padding(.vertical, 9)
                    if index != jobs.count - 1 {
                        Divider().background(Theme.stroke.opacity(0.7))
                    }
                }
            }
            Divider().background(Theme.stroke)
            Text("每项 8 秒。只做 pread，不创建、不写入任何文件。普通 iOS 设备无法绕过沙箱访问块设备，因此此页默认不可运行。")
                .font(.system(size: 9))
                .foregroundColor(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
