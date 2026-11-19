import DNSLeakCore
import SwiftUI

struct RepairView: View {
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
                    configurationCard
                    applyCard
                }
                .frame(width: 350)
            }

            if let report = model.lastReport {
                reportCard(report)
            }
        }
    }

    private var optionsCard: some View {
        PanelSurface(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("可选修复项")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("勾选项同时用于手动修复与实时守护的自动恢复")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(
                        text: "\(model.selectedProtectionOptionCount) / \(FixOptionType.allCases.count) 已选择",
                        tint: GuardTheme.accent
                    )
                }
                .padding(16)

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                ForEach(FixOptionType.allCases) { option in
                    FixOptionCard(
                        option: option,
                        findingCount: model.optionCount(option),
                        isOn: Binding(
                            get: { model.selection.isEnabled(option) },
                            set: { model.set(option, enabled: $0) }
                        )
                    )
                    if option != FixOptionType.allCases.last {
                        Rectangle()
                            .fill(Color.primary.opacity(0.05))
                            .frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private var safetyCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("写入保护", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GuardTheme.safe)
                    Spacer()
                    Text("原子写入")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ParagraphNote(
                    icon: "externaldrive.fill.badge.timemachine",
                    text: "每个文件写入前会在同目录创建 .dnsleakguard-backup.yyyyMMdd-HHmmss 备份。",
                    tint: GuardTheme.safe
                )
                ParagraphNote(
                    icon: "lock.doc.fill",
                    text: "不会修改订阅 URL 或 profiles/ 下的原始订阅文件；规则类修复只作用于当前生成配置。",
                    tint: GuardTheme.safe
                )
                ParagraphNote(
                    icon: "arrow.triangle.2.circlepath",
                    text: "写入后先做一次静态复检，再通过 Clash Verge UNIX 控制接口请求重载。",
                    tint: GuardTheme.safe
                )
            }
        }
    }

    private var configurationCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 13) {
                Text("修复参数")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                VStack(alignment: .leading, spacing: 5) {
                    Text("DNS 绑定代理组")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker(
                        "DNS 绑定代理组",
                        selection: Binding(
                            get: { model.selectedProxyGroup ?? "__auto__" },
                            set: {
                                model.setSelectedProxyGroup(
                                    $0 == "__auto__" ? nil : $0
                                )
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

                Toggle(
                    "同步修复 DNS 覆写并保持启用",
                    isOn: Binding(
                        get: { model.persistDNSOverride },
                        set: { model.setPersistDNSOverride($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("开启后同时维护 dns_config.yaml，并把当前订阅的 Clash Verge DNS 覆写开关设为启用。订阅源变化后，实时守护会再次恢复。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.selection.addNoResolve {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(GuardTheme.warning)
                        Text("no-resolve 可能改变 GEOIP 对域名请求的分流结果，只建议在明确理解规则顺序时开启。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .background(GuardTheme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }

    private var applyCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("执行")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("所有修复项均需显式勾选")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    IconTile(symbol: "wrench.and.screwdriver.fill", tint: GuardTheme.purple, size: 34)
                }

                Button {
                    Task { await model.applySelectedOnly() }
                } label: {
                    Label("应用已勾选修复", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(
                    model.isBusy
                        || model.selectedProtectionOptionCount == 0
                        || model.workspace == nil
                )

                Button {
                    Task { await model.runOneClick() }
                } label: {
                    Label("修复后在线复验", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(
                    model.isBusy
                        || model.selectedProtectionOptionCount == 0
                        || model.workspace == nil
                )

                HStack {
                    Button("活动配置") {
                        model.revealActiveConfig()
                    }
                    .buttonStyle(CompactButtonStyle())
                    Button("备份目录") {
                        model.revealBackups()
                    }
                    .buttonStyle(CompactButtonStyle())
                }
            }
        }
    }

    private func reportCard(_ report: FixApplicationReport) -> some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("最近一次修复", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    StatusBadge(
                        text: report.reloadSucceeded ? "已重载" : "等待重载",
                        tint: report.reloadSucceeded ? GuardTheme.safe : GuardTheme.warning,
                        icon: report.reloadSucceeded ? "checkmark.circle.fill" : "clock.fill"
                    )
                }

                HStack(spacing: 24) {
                    reportMetric("变更", "\(report.changeCount)")
                    reportMetric("文件", "\(report.changedFiles.count)")
                    reportMetric("备份", "\(report.backups.count)")
                    reportMetric("修复项", "\(report.appliedActions.count)")
                    Spacer()
                }

                if !report.appliedActions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(report.appliedActions) { action in
                            Text(action.title)
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(GuardTheme.accent.opacity(0.08), in: Capsule())
                        }
                    }
                }

                Text(report.reloadMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                if !report.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(report.notes.prefix(6).enumerated()), id: \.offset) { _, note in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(GuardTheme.accent)
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

private struct FixOptionCard: View {
    let option: FixOptionType
    let findingCount: Int
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        (isOn ? GuardTheme.accent : Color.secondary)
                            .opacity(0.10)
                    )
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? GuardTheme.accent : .secondary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(option.title)
                        .font(.system(size: 12.5, weight: .semibold))
                    if option.isAdvanced {
                        Text("高级")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(GuardTheme.warning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(GuardTheme.warning.opacity(0.10), in: Capsule())
                    }
                    if findingCount > 0 {
                        Text("\(findingCount) 项发现")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(GuardTheme.accent)
                    } else {
                        Text("预防性")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(option.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var symbol: String {
        switch option {
        case .removePlaintextDNS: "rectangle.slash.fill"
        case .bindDNSToProxy: "point.3.connected.trianglepath.dotted"
        case .enableMihomoDNS: "power.circle.fill"
        case .fixDNSKeyTypos: "textformat.abc.dottedunderline"
        case .addNoResolve: "arrow.triangle.branch"
        }
    }
}
