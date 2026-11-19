import DNSLeakCore
import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    let openDashboard: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            header
            statusHero
            actions
            protectionCard
            recentEvent
            footer
        }
        .padding(14)
        .frame(width: 366)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(
                    colors: [
                        GuardTheme.accent.opacity(0.055),
                        Color.clear,
                        GuardTheme.purple.opacity(0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconTile(symbol: "shield.lefthalf.filled", tint: GuardTheme.accent, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("DNS Leak Guard")
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                Text("原生 DNS 泄露守护")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(
                text: model.workspace?.isClashVergeRunning == true ? "已连接" : "Clash 离线",
                tint: model.workspace?.isClashVergeRunning == true ? GuardTheme.safe : GuardTheme.warning
            )
        }
    }

    private var statusHero: some View {
        PanelSurface(padding: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(heroTint.opacity(0.10))
                    Circle()
                        .stroke(heroTint.opacity(0.20), lineWidth: 1)
                    Image(systemName: heroSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(heroTint)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(heroTitle)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(heroDetail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 9) {
                        Label("评分 \(model.score)", systemImage: "gauge.with.dots.needle.33percent")
                        Label("\(model.riskCount) 风险", systemImage: "exclamationmark.triangle")
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.runDetection() }
            } label: {
                Label("检测", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(model.isBusy)

            Button {
                Task { await model.runOneClick() }
            } label: {
                Label("修复", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(model.isBusy || model.workspace == nil)
        }
    }

    private var protectionCard: some View {
        PanelSurface(padding: 13) {
            VStack(spacing: 10) {
                HStack {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(model.protectionState.tint)
                            .frame(width: 7, height: 7)
                        Text("实时守护")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(model.protectionState.label)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.protectionEnabled },
                            set: { model.setProtectionEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                HStack {
                    Text(model.protectionStatusText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Picker(
                        "模式",
                        selection: Binding(
                            get: { model.protectionMode },
                            set: { model.setProtectionMode($0) }
                        )
                    ) {
                        ForEach(ProtectionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.mini)
                    .frame(width: 83)
                    .disabled(!model.protectionEnabled)
                }
            }
        }
    }

    @ViewBuilder
    private var recentEvent: some View {
        if let event = model.protectionEvents.first {
            HStack(spacing: 8) {
                Image(systemName: event.kind.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.protectionState.tint)
                Text(event.message)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(event.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        } else {
            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9.5))
                Text("实时守护默认关闭，所有自动写入均需手动开启。")
                    .font(.system(size: 9.5))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Button(action: openDashboard) {
                Label("打开控制台", systemImage: "macwindow")
            }
            .buttonStyle(CompactButtonStyle())

            Button {
                model.openBrowserLeaks()
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(CompactButtonStyle())
            .help("BrowserLeaks DNS 测试")

            Spacer()

            Text(String(format: "%.1f MB", model.memoryMegabytes))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Button(action: quit) {
                Image(systemName: "power")
            }
            .buttonStyle(CompactButtonStyle())
            .help("退出 DNS Leak Guard")
        }
    }

    private var heroTitle: String {
        if model.errorMessage != nil, model.workspace == nil {
            return "未找到 Clash Verge"
        }
        if model.protectionEnabled {
            return model.protectionStatusText
        }
        return model.headline
    }

    private var heroDetail: String {
        if let result = model.liveResult {
            return result.message
        }
        if let last = model.lastProtectionCheck {
            return "上次检查 \(last.formatted(date: .omitted, time: .shortened)) · \(model.analysis?.findings.count ?? 0) 项发现"
        }
        return "静态配置审计 + 在线解析路径复验"
    }

    private var heroSymbol: String {
        if model.errorMessage != nil, model.workspace == nil {
            return "questionmark.shield.fill"
        }
        if model.protectionEnabled {
            return model.protectionIconName
        }
        return model.riskCount == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
    }

    private var heroTint: Color {
        if model.errorMessage != nil, model.workspace == nil {
            return GuardTheme.warning
        }
        if model.protectionEnabled {
            return model.protectionState.tint
        }
        return model.riskCount == 0 ? GuardTheme.safe : GuardTheme.danger
    }
}
