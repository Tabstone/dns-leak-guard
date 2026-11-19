import AppKit
import DNSLeakCore
import SwiftUI

struct RoutingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            if let error = model.errorMessage {
                ErrorBannerView(message: error)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    optionsCard
                    safetyCard
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    previewCard
                    applyCard
                }
                .frame(width: 386)
            }

            if let report = model.ruleReport {
                reportCard(report)
            }
        }
        .task {
            if model.rulePreview == nil {
                await model.refreshRulePreview()
            }
        }
    }

    private var optionsCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("规则模式合并")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("通过 Clash Verge Merge 持久化，并同步当前活动配置立即生效。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    IconTile(
                        symbol: "arrow.triangle.branch",
                        tint: GuardTheme.purple,
                        size: 36
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("代理组")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker(
                        "规则代理组",
                        selection: Binding(
                            get: { model.selectedProxyGroup ?? "__auto__" },
                            set: {
                                model.setSelectedProxyGroup(
                                    $0 == "__auto__" ? nil : $0
                                )
                                Task { await model.refreshRulePreview() }
                            }
                        )
                    ) {
                        Text("自动选择推荐组").tag("__auto__")
                        ForEach(model.analysis?.proxyGroups ?? []) { group in
                            Text("\(group.name) · \(group.type)").tag(group.name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                RuleToggleRow(
                    title: "WhatsApp / Meta 即时通讯",
                    detail: "显式代理 whatsapp.com、whatsapp.net、wa.me 等域名，修复客户端登录与二维码连接。",
                    isOn: Binding(
                        get: { model.ruleIncludeWhatsApp },
                        set: { model.setRuleIncludeWhatsApp($0) }
                    )
                )
                RuleToggleRow(
                    title: "追加 Meta 全系域名",
                    detail: "范围更广，会同时代理 Facebook、Instagram、Messenger 与 Threads。默认关闭。",
                    isOn: Binding(
                        get: { model.ruleIncludeMeta },
                        set: { model.setRuleIncludeMeta($0) }
                    ),
                    warning: true
                )
                RuleToggleRow(
                    title: "局域网与私有地址直连",
                    detail: "在规则最前加入 10/8、172.16/12、192.168/16、链路本地与回环地址。",
                    isOn: Binding(
                        get: { model.ruleIncludeLocalDirect },
                        set: { model.setRuleIncludeLocalDirect($0) }
                    )
                )
                RuleToggleRow(
                    title: "Loyalsoldier 代理白名单",
                    detail: "通过 RULE-SET 加载 proxy.txt，仅将常见海外域名加入代理，不在 Merge 中整体替换 rules。",
                    isOn: Binding(
                        get: { model.ruleIncludeLoyalsoldierProxy },
                        set: { model.setRuleIncludeLoyalsoldierProxy($0) }
                    )
                )
                RuleToggleRow(
                    title: "Loyalsoldier 私有域名直连",
                    detail: "加载 private.txt，避免局域网和保留域名被错误代理。",
                    isOn: Binding(
                        get: { model.ruleIncludeLoyalsoldierPrivate },
                        set: { model.setRuleIncludeLoyalsoldierPrivate($0) }
                    )
                )
                RuleToggleRow(
                    title: "Loyalsoldier 国内域名直连",
                    detail: "加载 direct.txt，把常见中国大陆域名放在代理规则之前直连。",
                    isOn: Binding(
                        get: { model.ruleIncludeLoyalsoldierDirect },
                        set: { model.setRuleIncludeLoyalsoldierDirect($0) }
                    ),
                    isLocked: model.ruleForceProxyFallback
                )
                RuleToggleRow(
                    title: "国内直连、其余全部代理",
                    detail: "在私有/国内直连规则之后加入 MATCH，接管订阅原有分流。适合“白名单直连”模式；默认关闭。",
                    isOn: Binding(
                        get: { model.ruleForceProxyFallback },
                        set: { model.setRuleForceProxyFallback($0) }
                    ),
                    warning: true
                )
                RuleToggleRow(
                    title: "仅缺失时补齐最终 MATCH",
                    detail: "若现有配置没有 MATCH 才追加；不会把 MATCH 放在订阅规则之前拦截全部流量。",
                    isOn: Binding(
                        get: { model.ensureFinalMatch },
                        set: { model.setEnsureFinalMatch($0) }
                    ),
                    isLocked: model.ruleForceProxyFallback
                )
            }
        }
    }

    private var previewCard: some View {
        PanelSurface(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("写入预览")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("只显示 DNSLeakGuard 管理的片段")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("刷新") {
                        Task { await model.refreshRulePreview() }
                    }
                    .buttonStyle(CompactButtonStyle())
                }
                .padding(14)

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                ScrollView {
                    Text(
                        model.rulePreview?.generatedSections
                            ?? "点击“刷新”生成预览。"
                    )
                    .font(.system(size: 9.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                }
                .frame(minHeight: 260, maxHeight: 350)

                if let preview = model.rulePreview {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Merge: \(preview.mergeFile.lastPathComponent)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(
                            "\(preview.prependRules.count) 条前置规则 · "
                                + (preview.mergeWillChange ? "Merge 待更新" : "Merge 已最新")
                                + " · "
                                + (preview.activeWillChange ? "活动配置待更新" : "活动配置已最新")
                        )
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                }
            }
        }
    }

    private var applyCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 11) {
                Text("执行")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("写入前分别备份 Merge 与活动配置；不修改订阅原文件。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Button {
                    Task { await model.applyRulePlan() }
                } label: {
                    Label("写入 Merge 并立即生效", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(
                    model.isBusy
                        || model.workspace == nil
                        || model.analysis == nil
                        || model.selectedProxyGroup == nil
                )

                Button("查看 Merge 文件") {
                    if let url = model.rulePreview?.mergeFile {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .buttonStyle(CompactButtonStyle())
                .disabled(model.rulePreview == nil)
            }
        }
    }

    private var safetyCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 9) {
                Label("规则安全边界", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GuardTheme.safe)
                ParagraphNote(
                    icon: "text.insert",
                    text: "使用 prepend-rules 在订阅规则之前插入，不写顶层 rules，也不会清空或重排原有分流。",
                    tint: GuardTheme.safe
                )
                ParagraphNote(
                    icon: "externaldrive.fill.badge.timemachine",
                    text: "Merge 与活动配置写前各自创建 .dnsleakguard-backup 备份，并采用原子替换。",
                    tint: GuardTheme.safe
                )
                ParagraphNote(
                    icon: "arrow.triangle.2.circlepath",
                    text: "Merge 决定订阅刷新后的持久结果；活动配置用于本次立即生效。两者会同步写入。",
                    tint: GuardTheme.safe
                )
                if model.ruleForceProxyFallback {
                    ParagraphNote(
                        icon: "exclamationmark.triangle.fill",
                        text: "“国内直连、其余全部代理”正在开启：托管 MATCH 会位于订阅规则之前，订阅中的其他规则仍保留但不再参与命中。",
                        tint: GuardTheme.warning
                    )
                }
            }
        }
    }

    private func reportCard(
        _ report: ClashRuleApplicationReport
    ) -> some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("最近一次规则写入", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    StatusBadge(
                        text: report.reloadSucceeded ? "已重载" : "等待重载",
                        tint: report.reloadSucceeded ? GuardTheme.safe : GuardTheme.warning
                    )
                }
                HStack(spacing: 22) {
                    reportMetric("规则", "\(report.ruleCount)")
                    reportMetric("文件", "\(report.changedFiles.count)")
                    reportMetric("备份", "\(report.backups.count)")
                    Spacer()
                }
                Text(report.reloadMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                ForEach(Array(report.notes.prefix(6).enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(GuardTheme.purple)
                            .frame(width: 4, height: 4)
                            .padding(.top, 5)
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func reportMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct RuleToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var warning = false
    var isLocked = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(
                systemName: warning
                    ? "exclamationmark.triangle.fill"
                    : "checkmark.seal.fill"
            )
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(warning ? GuardTheme.warning : GuardTheme.accent)
            .frame(width: 17)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.8))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isLocked)
        }
        .padding(.vertical, 2)
    }
}
