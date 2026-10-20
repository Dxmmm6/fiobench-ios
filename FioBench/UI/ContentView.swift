import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabBar
                progressLine
                statusLine

                TabView(selection: $model.tab) {
                    BenchmarkPage().tag(AppTab.bench)
                    CDMPage().tag(AppTab.cdm)
                    ASSSDPage().tag(AppTab.assd)
                    CustomPage().tag(AppTab.custom)
                    StressPage().tag(AppTab.stress)
                    RawPage().tag(AppTab.raw)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.bootstrap() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("fio 存储测试")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("\(model.deviceModel) · \(model.osVersion) · \(model.abi)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.sub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: 4)

            HStack(spacing: 0) {
                unitButton("MB/s", selected: !model.useIOPS) {
                    model.useIOPS = false
                }
                unitButton("IOPS", selected: model.useIOPS) {
                    model.useIOPS = true
                }
            }
            .padding(2)
            .background(Theme.field)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func unitButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : Theme.sub)
                .frame(width: 44, height: 25)
                .background(selected ? Theme.accent : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.tab = tab
                    }
                }) {
                    VStack(spacing: 5) {
                        Text(tab.title)
                            .font(.system(size: 11, weight: model.tab == tab ? .bold : .regular))
                            .foregroundColor(model.tab == tab ? Theme.accent : Theme.sub)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Rectangle()
                            .fill(model.tab == tab ? Theme.accent : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 11)
    }

    @ViewBuilder
    private var progressLine: some View {
        if model.running {
            IndeterminateProgressBar()
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.top, 7)
                .transition(.opacity)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.running ? Theme.accent : Theme.sub.opacity(0.6))
                .frame(width: 5, height: 5)
            Text(model.status)
                .font(.system(size: 10))
                .foregroundColor(Theme.sub)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .padding(.horizontal, 14)
    }
}

struct IndeterminateProgressBar: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.field)
                    .frame(height: 3)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(24, proxy.size.width * 0.42), height: 3)
                    .offset(x: animate ? proxy.size.width : -proxy.size.width * 0.42)
            }
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
        }
    }
}
