import DNSLeakCore
import SwiftUI

struct LiveDNSView: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 16) {
            if let error = model.errorMessage {
                ErrorBannerView(message: error)
            }

            selectionCard

            if model.providerResults.isEmpty {
                PanelSurface {
                    EmptyStateView(
                        icon: "globe.desk",
                        title: "选择站点后开始检测",
                        detail: "每个站点会独立返回解析器 IP、ISP 与地区。网页复核站点不会伪造检测结果。"
                    )
                }
            } else {
                summaryCard
                resultGrid
            }

            ParagraphNote(
                icon: "checkmark.seal.fill",
                text: "官方 API 与页面同源接口会直接执行 DNS 探测；Whoer 当前被 Cloudflare Managed Challenge 拦截，只提供网页复核。所有结果均标注实际方法，不把网页跳转当作成功检测。",
                tint: GuardTheme.safe
            )
            .padding(.horizontal, 3)
        }
    }

    private var selectionCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("多站点 DNS 测漏")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("可单选或同时勾选多个站点；原生探测并发执行，互不覆盖。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(
                        text: "\(model.selectedProviders.count) / \(DNSLeakProviderID.allCases.count) 已选择",
                        tint: GuardTheme.accent
                    )
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(DNSLeakProviderID.allCases) { provider in
                        providerOption(provider)
                    }
                }

                HStack(spacing: 8) {
                    Button("全选") {
                        model.selectAllProviders()
                    }
                    .buttonStyle(CompactButtonStyle())
                    .disabled(model.isBusy)

                    Button("清空") {
                        model.clearSelectedProviders()
                    }
                    .buttonStyle(CompactButtonStyle())
                    .disabled(model.isBusy || model.selectedProviders.isEmpty)

                    Spacer()

                    if model.isBusy {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text(model.providerProgressText)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(model.providerProgressText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        Task { await model.runLiveTestOnly() }
                    } label: {
                        Label("检测所选站点", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(model.isBusy || model.selectedProviders.isEmpty)
                }
            }
        }
    }

    private func providerOption(
        _ provider: DNSLeakProviderID
    ) -> some View {
        let selected = model.selectedProviders.contains(provider)
        return Button {
            model.setProviderSelected(provider, enabled: !selected)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: selected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? GuardTheme.accent : Color.secondary)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(provider.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(provider.integration.label)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(provider.integration.tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                provider.integration.tint.opacity(0.10),
                                in: Capsule()
                            )
                    }
                    Text(provider.methodDescription)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(
                selected
                    ? GuardTheme.accent.opacity(0.055)
                    : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected
                            ? GuardTheme.accent.opacity(0.20)
                            : Color.primary.opacity(0.055),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
    }

    private var summaryCard: some View {
        PanelSurface {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(summaryTint.opacity(0.11))
                    Circle()
                        .stroke(summaryTint.opacity(0.22), lineWidth: 1)
                    Image(systemName: summarySymbol)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(summaryTint)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 5) {
                    Text(summaryTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(summaryDetail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(model.providerResolverCount)")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("合并解析器")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var resultGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(model.providerResultsInDisplayOrder) { result in
                providerResultCard(result)
            }
        }
    }

    private func providerResultCard(
        _ result: DNSLeakProviderResult
    ) -> some View {
        PanelSurface(padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: result.outcome.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(result.outcome.tint)
                    Text(result.provider.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Spacer()
                    StatusBadge(
                        text: result.outcome.label,
                        tint: result.outcome.tint
                    )
                }

                Text(result.message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !result.observations.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(result.observations.prefix(5)) { observation in
                            HStack(spacing: 7) {
                                Text(observation.ip)
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                Text(
                                    [observation.isp, observation.location]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · ")
                                )
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        if result.observations.count > 5 {
                            Text("另有 \(result.observations.count - 5) 个地址")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(9)
                    .background(
                        Color.primary.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }

                HStack(spacing: 7) {
                    Text(result.method)
                        .font(.system(size: 8.8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                    Spacer()
                    Button("网页") {
                        model.openProviderPage(result.provider)
                    }
                    .buttonStyle(CompactButtonStyle())
                }
            }
        }
    }

    private var summaryTint: Color {
        model.hasMultipleResolverPaths ? GuardTheme.warning : GuardTheme.safe
    }

    private var summarySymbol: String {
        model.hasMultipleResolverPaths
            ? "exclamationmark.shield.fill"
            : "checkmark.shield.fill"
    }

    private var summaryTitle: String {
        model.hasMultipleResolverPaths
            ? "检测到多解析器路径"
            : "所选原生站点结果一致"
    }

    private var summaryDetail: String {
        if let live = model.liveResult {
            return live.message
        }
        return "所选站点均未返回可解析结果；请查看各站点失败原因。"
    }
}
