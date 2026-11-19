import DNSLeakCore
import SwiftUI

struct FindingsView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var state = FindingsViewState()

    private var findings: [Finding] {
        let all = model.analysis?.findings ?? []
        let categorized: [Finding]
        switch state.filter {
        case .all:
            categorized = all
        case .risks:
            categorized = all.filter {
                $0.category == .confirmedLeak || $0.category == .possibleLeak
            }
        case .config:
            categorized = all.filter {
                $0.category == .configError || $0.category == .hardening
            }
        case .notes:
            categorized = all.filter {
                $0.category == .redundantResolution || $0.severity == .info
            }
        }
        guard !state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return categorized
        }
        let needle = state.query.lowercased()
        return categorized.filter {
            $0.title.lowercased().contains(needle)
                || $0.code.lowercased().contains(needle)
                || $0.detail.lowercased().contains(needle)
                || $0.locations.contains {
                    $0.snippet.lowercased().contains(needle)
                }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if let error = model.errorMessage {
                ErrorBannerView(message: error)
            }

            HStack(alignment: .top, spacing: 16) {
                summaryCard
                riskFilterCard
                    .frame(width: 340)
            }

            PanelSurface(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("发现列表")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text("\(findings.count) 项符合当前筛选")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("搜索规则或地址", text: $state.query)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5))
                                .frame(width: 150)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.045), in: Capsule())

                        Picker("筛选", selection: $state.filter) {
                            ForEach(FindingFilter.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                    .padding(16)

                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)

                    if model.analysis == nil {
                        EmptyStateView(
                            icon: "shield.checkered",
                            title: "尚未扫描",
                            detail: "连接 Clash Verge 后会自动读取当前活动配置。"
                        )
                    } else if findings.isEmpty {
                        EmptyStateView(
                            icon: "checkmark.shield.fill",
                            title: state.query.isEmpty ? "此分类没有发现" : "没有匹配结果",
                            detail: state.query.isEmpty
                                ? "切换筛选查看其它类别，或重新运行检测。"
                                : "尝试清空搜索关键字。"
                        )
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(findings) { finding in
                                NewFindingRow(finding: finding)
                                if finding.id != findings.last?.id {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.055))
                                        .frame(height: 1)
                                        .padding(.leading, 54)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        PanelSurface {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            (model.riskCount == 0 ? GuardTheme.safe : GuardTheme.warning)
                                .opacity(0.10)
                        )
                    Image(systemName: model.riskCount == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(model.riskCount == 0 ? GuardTheme.safe : GuardTheme.warning)
                }
                .frame(width: 70, height: 70)

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.riskCount == 0 ? "未发现 DNS 风险" : "发现 \(model.riskCount) 项 DNS 风险")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("静态规则链与 DNS 配置同时检查")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Label(
                            "\(model.analysis?.findings.count ?? 0) 项发现",
                            systemImage: "list.bullet"
                        )
                        Label(
                            "\(model.configErrorCount) 项配置错误",
                            systemImage: "exclamationmark.triangle"
                        )
                        Label(
                            "\(model.analysis?.actionableFindingCount ?? 0) 项可修复",
                            systemImage: "wrench"
                        )
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var riskFilterCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text("审计方法")
                    .font(.system(size: 12.5, weight: .semibold))
                ParagraphNote(
                    icon: "1.circle.fill",
                    text: "检查明文 DNS、未绑定代理的加密 DNS、失效策略组与键名拼写。"
                )
                ParagraphNote(
                    icon: "2.circle.fill",
                    text: "分析 GEOIP / IP-CIDR / RULE-SET 是否会先触发本地解析。"
                )
                ParagraphNote(
                    icon: "3.circle.fill",
                    text: "在线探测用于验证多解析器路径，不替代配置语义审计。"
                )
            }
        }
    }
}

private final class FindingsViewState: ObservableObject {
    @Published var filter: FindingFilter = .all
    @Published var query = ""
}

private enum FindingFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case risks = "泄露"
    case config = "配置"
    case notes = "提示"

    var id: String { rawValue }
}

private struct NewFindingRow: View {
    let finding: Finding
    @StateObject private var state = FindingExpansionState()

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    state.expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(finding.severity.tint)
                        .frame(width: 4, height: 34)

                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(finding.severity.tint.opacity(0.10))
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(finding.severity.tint)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(finding.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(finding.code)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                        Text(finding.detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(state.expanded ? nil : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 10)

                    Text(finding.category.label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(finding.severity.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(finding.severity.tint.opacity(0.09), in: Capsule())

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(state.expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if state.expanded {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.max.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GuardTheme.warning)
                            .frame(width: 16)
                        Text(finding.recommendation)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !finding.locations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("相关位置")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            ForEach(Array(finding.locations.prefix(6))) { location in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("L\(location.line)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(GuardTheme.accent)
                                        .frame(width: 36, alignment: .leading)
                                    Text(location.snippet)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }

                    if let fix = finding.fix {
                        HStack(spacing: 6) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("可修复：\(fix.title)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(GuardTheme.accent)
                    }
                }
                .padding(.leading, 62)
                .padding(.trailing, 24)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var symbol: String {
        switch finding.category {
        case .confirmedLeak: "drop.triangle.fill"
        case .possibleLeak: "exclamationmark.triangle.fill"
        case .configError: "xmark.octagon.fill"
        case .redundantResolution: "arrow.triangle.2.circlepath"
        case .hardening: "shield.lefthalf.filled"
        }
    }
}

private final class FindingExpansionState: ObservableObject {
    @Published var expanded = false
}
