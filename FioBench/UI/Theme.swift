import SwiftUI

enum Theme {
    static let bg = Color(red: 14.0 / 255.0, green: 16.0 / 255.0, blue: 19.0 / 255.0)
    static let card = Color(red: 25.0 / 255.0, green: 28.0 / 255.0, blue: 33.0 / 255.0)
    static let field = Color(red: 34.0 / 255.0, green: 38.0 / 255.0, blue: 45.0 / 255.0)
    static let text = Color(red: 233.0 / 255.0, green: 236.0 / 255.0, blue: 239.0 / 255.0)
    static let sub = Color(red: 139.0 / 255.0, green: 145.0 / 255.0, blue: 154.0 / 255.0)
    static let accent = Color(red: 76.0 / 255.0, green: 141.0 / 255.0, blue: 255.0 / 255.0)
    static let green = Color(red: 46.0 / 255.0, green: 204.0 / 255.0, blue: 113.0 / 255.0)
    static let amber = Color(red: 245.0 / 255.0, green: 165.0 / 255.0, blue: 36.0 / 255.0)
    static let red = Color(red: 255.0 / 255.0, green: 95.0 / 255.0, blue: 86.0 / 255.0)
    static let stroke = Color.white.opacity(0.065)
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

struct PageScroll<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
    }
}

struct CardTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.sub)
            }
        }
    }
}

struct KeyValueLine: View {
    let key: String
    let value: String
    var color: Color = Theme.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(size: 12))
                .foregroundColor(Theme.sub)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(color)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct IntStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String = ""
    var step: Int = 1

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(Theme.sub)
            Spacer()
            HStack(spacing: 0) {
                stepButton("-", enabled: value > range.lowerBound) {
                    value = max(range.lowerBound, value - step)
                }
                Text("\(value)\(suffix)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.text)
                    .frame(minWidth: 66)
                    .multilineTextAlignment(.center)
                stepButton("+", enabled: value < range.upperBound) {
                    value = min(range.upperBound, value + step)
                }
            }
            .background(Theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func stepButton(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: label == "+" ? "plus" : "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(enabled ? Theme.text : Theme.sub.opacity(0.35))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.sub)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }
}

struct TargetPicker: View {
    @Binding var target: StorageTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ForEach(StorageTarget.allCases) { item in
                    Button(action: {
                        if item.isAvailable { target = item }
                    }) {
                        Text(item.rawValue)
                            .font(.system(size: 11, weight: target == item ? .semibold : .regular))
                            .foregroundColor(target == item ? .white : (item.isAvailable ? Theme.sub : Theme.sub.opacity(0.35)))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(target == item ? Theme.accent : Theme.field)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!item.isAvailable)
                }
                Spacer()
            }
            Text("iOS 没有 Android 的外置 SD 挂载点，测试固定在应用容器")
                .font(.system(size: 9))
                .foregroundColor(Theme.sub.opacity(0.8))
        }
    }
}

struct Chips: View {
    let options: [String]
    @Binding var selected: Int
    var compact: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options.indices, id: \.self) { index in
                    Button(action: { selected = index }) {
                        Text(options[index])
                            .font(.system(size: compact ? 10 : 11,
                                          weight: selected == index ? .semibold : .regular))
                            .foregroundColor(selected == index ? .white : Theme.sub)
                            .padding(.horizontal, compact ? 8 : 10)
                            .padding(.vertical, compact ? 5 : 6)
                            .background(selected == index ? Theme.accent : Theme.field)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(enabled ? .white : Theme.sub.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(enabled ? Theme.accent : Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(enabled ? Theme.text : Theme.sub.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct HintText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundColor(Theme.sub.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Theme.sub)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
}

struct LabeledValue: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.text
    var mono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Theme.sub)
            Text(value)
                .font(.system(size: 13, weight: .semibold,
                              design: mono ? .monospaced : .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
