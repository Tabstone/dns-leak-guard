import DNSLeakCore
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    let openSection: (DashboardSection) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let error = model.errorMessage {
                ErrorBannerView(
                    message: error,
                    actionTitle: model.workspace == nil ? "重新连接" : nil,
                    action: model.workspace == nil ? {
                        Task { await model.bootstrap() }
                    } : nil
                )
            }

            HStack(alignment: .top, spacing: 16) {
                overviewHero
                protectionHero
                    .frame(width: 318)
                    .frame(minHeight: 188)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                MetricTile(
                    title: "配置风险",
                    value: "\(model.riskCount)",
                    detail: model.riskCount == 0 ? "未发现 DNS 泄露风险" : "建议查看诊断",
                    symbol: "exclamationmark.shield.fill",
                    tint: model.riskCount == 0 ? GuardTheme.safe : GuardTheme.danger
                )
                MetricTile(
                    title: "在线 DNS",
                    value: liveValue,
                    detail: liveDetail,
                    symbol: "antenna.radiowaves.left.and.right",
                    tint: model.liveResult?.outcome.tint ?? GuardTheme.accent
                )
                MetricTile(
                    title: "Clash 运行时",
                    value: runtimeMode,
                    detail: model.runtimeStatus?.tunEnabled == true ? "TUN 已启用" : "TUN 状态未知",
                    symbol: "network",
                    tint: GuardTheme.purple
                )
                MetricTile(
                    title: "内存占用",
                    value: String(format: "%.1f MB", model.memoryMegabytes),
                    detail: "仅窗口打开时刷新",
                    symbol: "memorychip.fill",
                    tint: GuardTheme.safe
                )
            }

            if let live = model.liveResult {
                liveSummary(live)
            }

            HStack(alignment: .top, spacing: 16) {
                quickActions
                    .frame(maxWidth: .infinity)
                workspaceCard
                    .frame(width: 360)
            }

            if let warnings = model.health?.warnings, !warnings.isEmpty {
                warningsCard(warnings)
            }

            ParagraphNote(
                icon: "info.circle.fill",
                text: "“在线 DNS”使用与 BrowserLeaks 同源的随机子域探测，仅用于多解析器路径辅助判断；最终结论仍应结合 browserleaks.com/dns 与当前 Clash 规则模式复核。"
            )
            .padding(.horizontal, 3)
        }
    }

    private var overviewHero: some View {
        PanelSurface {
            HStack(spacing: 22) {
                ScoreRing(score: model.score, size: 112)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        StatusBadge(
                            text: model.analysis == nil ? "等待扫描" : "配置已扫描",
                            tint: model.riskCount == 0 ? GuardTheme.safe : GuardTheme.warning,
                            icon: model.riskCount == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                        )
                        if model.protectionEnabled {
                            StatusBadge(
                                text: model.protectionState.label,
                                tint: model.protectionState.tint,
                                icon: "shield.fill"
                            )
                        }
                    }

                    Text(model.headline)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(model.analysis?.totalLines ?? 0) 行活动配置 · \(model.analysis?.findings.count ?? 0) 项发现")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            Task { await model.runDetection() }
                        } label: {
                            Label("完整检测", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(model.isBusy)

                        Button {
                            openSection(.repair)
                        } label: {
                            Label("查看修复项", systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(CompactButtonStyle())
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 188)
    }

    private var protectionHero: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("实时守护")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    StatusBadge(
                        text: model.protectionState.label,
                        tint: model.protectionState.tint,
                        icon: "dot.radiowaves.left.and.right"
                    )
                }

                Text(model.protectionEnabled ? model.protectionStatusText : "默认关闭，按需开启")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(2)

                Text(
                    model.protectionMode == .autoRepair
                        ? "配置变动后自动恢复已勾选的 DNS 保护项。"
                        : "配置变动后仅提醒，不写入文件。"
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                HStack {
                    Toggle(
                        "启用",
                        isOn: Binding(
                            get: { model.protectionEnabled },
                            set: { model.setProtectionEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Spacer()

                    Button("设置") {
                        openSection(.protection)
                    }
                    .buttonStyle(CompactButtonStyle())
                }
            }
        }
    }

    private var quickActions: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("快捷操作")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("所有写操作均先创建同目录备份")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    IconTile(symbol: "bolt.fill", tint: GuardTheme.warning, size: 31)
                }

                Button {
                    Task { await model.runOneClick() }
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("一键检测并修复")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("检测 → 勾选修复 → 重载 → 在线复验")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(
                        GuardTheme.accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)

                HStack(spacing: 8) {
                    Button("打开 BrowserLeaks") {
                        model.openBrowserLeaks()
                    }
                    .buttonStyle(CompactButtonStyle())

                    Button("活动配置") {
                        model.revealActiveConfig()
                    }
                    .buttonStyle(CompactButtonStyle())

                    Button("备份") {
                        model.revealBackups()
                    }
                    .buttonStyle(CompactButtonStyle())
                }
            }
        }
    }

    private var workspaceCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("工作区")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    StatusBadge(
                        text: model.workspace?.isClashVergeRunning == true ? "控制接口在线" : "控制接口离线",
                        tint: model.workspace?.isClashVergeRunning == true ? GuardTheme.safe : GuardTheme.warning
                    )
                }
                workspaceRow(
                    title: "活动配置",
                    detail: model.workspace?.activeConfig.lastPathComponent ?? "未找到",
                    symbol: "doc.text.fill"
                )
                workspaceRow(
                    title: "DNS 覆写",
                    detail: model.workspace?.dnsOverride?.lastPathComponent ?? "不可用",
                    symbol: "network.badge.shield.half.filled"
                )
                workspaceRow(
                    title: "DNS 覆写开关",
                    detail: model.health?.profileDNSOverrideEnabled == true
                        ? "已启用"
                        : model.health?.profileDNSOverrideEnabled == false ? "未启用" : "未知",
                    symbol: "switch.2"
                )
                HStack {
                    Text("上次更新")
                    Spacer()
                    Text(
                        model.lastUpdated?.formatted(date: .abbreviated, time: .shortened)
                            ?? "尚未更新"
                    )
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func workspaceRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(GuardTheme.accent)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Text(detail)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func liveSummary(_ result: LiveDNSTestResult) -> some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("在线 DNS 复验")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text(result.message)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    StatusBadge(
                        text: liveValue,
                        tint: result.outcome.tint,
                        icon: "antenna.radiowaves.left.and.right"
                    )
                    Button(result.outcome == .error ? "重试" : "BrowserLeaks") {
                        if result.outcome == .error {
                            Task { await model.runLiveTestOnly() }
                        } else {
                            model.openBrowserLeaks()
                        }
                    }
                    .buttonStyle(CompactButtonStyle())
                }

                if !result.observations.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(result.observations.prefix(6)) { observation in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(observation.isp)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .lineLimit(1)
                                Text(observation.location)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(observation.ip)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color.primary.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                    }
                }
            }
        }
    }

    private func warningsCard(_ warnings: [String]) -> some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("持久化边界", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GuardTheme.warning)
                    Spacer()
                    Text("\(warnings.count) 条")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(GuardTheme.warning)
                            .frame(width: 4, height: 4)
                            .padding(.top, 5)
                        Text(warning)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var liveValue: String {
        guard let result = model.liveResult else { return "待验证" }
        switch result.outcome {
        case .singleResolverPath: return "单一路径"
        case .multipleResolverPaths: return "\(result.uniqueISPs.count) 个 ISP"
        case .error: return "探测失败"
        }
    }

    private var liveDetail: String {
        guard let result = model.liveResult else { return "使用 BrowserLeaks 同源端点" }
        switch result.outcome {
        case .singleResolverPath:
            return "\(result.resolverCount) 地址 · \(result.uniqueLocations.first ?? "未知地区")"
        case .multipleResolverPaths:
            return "\(result.uniqueLocations.count) 个地区，需复核"
        case .error:
            return "网络或系统代理不可用"
        }
    }

    private var runtimeMode: String {
        switch model.runtimeStatus?.mode {
        case "rule": return "规则"
        case "global": return "全局"
        case "direct": return "直连"
        default: return "未知"
        }
    }
}
