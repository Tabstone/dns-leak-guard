import DNSLeakCore
import SwiftUI

struct ProtectionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            if let error = model.errorMessage {
                ErrorBannerView(message: error)
            }

            statusCard

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    modeCard
                    protectedItemsCard
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    scheduleCard
                    controlsCard
                }
                .frame(width: 356)
            }

            HStack(alignment: .top, spacing: 16) {
                eventHistoryCard
                    .frame(maxWidth: .infinity)
                boundariesCard
                    .frame(width: 356)
            }
        }
    }

    private var statusCard: some View {
        PanelSurface {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(model.protectionState.tint.opacity(0.10))
                    Circle()
                        .stroke(model.protectionState.tint.opacity(0.22), lineWidth: 1)
                    Image(systemName: model.protectionIconName)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(model.protectionState.tint)
                }
                .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("实时守护")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        StatusBadge(
                            text: model.protectionState.label,
                            tint: model.protectionState.tint,
                            icon: "dot.radiowaves.left.and.right"
                        )
                    }
                    Text(model.protectionEnabled ? model.protectionStatusText : "默认关闭，不会后台写入")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 15) {
                        Label(
                            "上次检查 \(formatted(model.lastProtectionCheck))",
                            systemImage: "clock"
                        )
                        Label(
                            "\(model.protectionRepairCount) 次自动恢复",
                            systemImage: "wrench.and.screwdriver"
                        )
                        if let blocked = model.protectionAutoRepairBlockedUntil, blocked > Date() {
                            Label(
                                "自动写入限流至 \(formatted(blocked))",
                                systemImage: "hourglass"
                            )
                            .foregroundStyle(GuardTheme.warning)
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 7) {
                    Toggle(
                        "启用实时守护",
                        isOn: Binding(
                            get: { model.protectionEnabled },
                            set: { model.setProtectionEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text("仅监听四个 Clash 配置文件")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var modeCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("保护模式")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("默认为仅监测；自动修复需要明确选择")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    IconTile(symbol: "slider.horizontal.3", tint: GuardTheme.purple, size: 34)
                }

                HStack(spacing: 10) {
                    ForEach(ProtectionMode.allCases) { mode in
                        Button {
                            model.setProtectionMode(mode)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Image(systemName: mode == .notifyOnly ? "bell.badge.fill" : "wand.and.stars")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(
                                            model.protectionMode == mode
                                                ? GuardTheme.accent
                                                : Color.secondary
                                        )
                                    Spacer()
                                    Image(systemName: model.protectionMode == mode ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(
                                            model.protectionMode == mode
                                                ? GuardTheme.accent
                                                : Color.secondary.opacity(0.5)
                                        )
                                }
                                Text(mode.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(mode.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                            .background {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(
                                        model.protectionMode == mode
                                            ? GuardTheme.accent.opacity(0.075)
                                            : Color.primary.opacity(0.028)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(
                                                model.protectionMode == mode
                                                    ? GuardTheme.accent.opacity(0.28)
                                                    : Color.primary.opacity(0.06),
                                                lineWidth: 1
                                            )
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.protectionEnabled)
                    }
                }
            }
        }
    }

    private var protectedItemsCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("受保护的不变量")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("守护与手动修复共用同一组勾选项")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(model.selectedProtectionOptionCount) 项")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GuardTheme.accent)
                }

                ForEach(FixOptionType.allCases) { option in
                    HStack(spacing: 9) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { model.selection.isEnabled(option) },
                                set: { model.set(option, enabled: $0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .controlSize(.small)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(option.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                if option.isAdvanced {
                                    Text("可能改变分流")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(GuardTheme.warning)
                                }
                            }
                            Text(option.detail)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                Toggle(
                    "同步保持 Clash Verge DNS 覆写启用",
                    isOn: Binding(
                        get: { model.persistDNSOverride },
                        set: { model.setPersistDNSOverride($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var scheduleCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 11) {
                Text("监测节奏")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Label("FSEvents 实时事件", systemImage: "bolt.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(GuardTheme.safe)
                Text("配置文件发生变化后约 0.9 秒合并扫描一次，不轮询整份规则。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.5)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("低频兜底扫描")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("事件丢失或睡眠唤醒后的保险")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(
                        "低频兜底扫描",
                        selection: Binding(
                            get: { model.fallbackScanMinutes },
                            set: { model.setFallbackScanMinutes($0) }
                        )
                    ) {
                        Text("关闭").tag(0)
                        Text("5 分钟").tag(5)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 104)
                }

                Divider().opacity(0.5)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("系统通知")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(model.notificationStatusText)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.notificationsEnabled },
                            set: { model.setNotificationsEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("登录时启动")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(model.launchAtLoginStatusText)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.launchAtLoginEnabled },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }

    private var controlsCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 11) {
                Text("控制")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Button {
                    Task { await model.scanProtectionNow() }
                } label: {
                    Label("立即静态复查", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(!model.protectionEnabled || model.isProtectionPaused)

                if model.isProtectionPaused {
                    Button {
                        model.resumeProtectionNow()
                    } label: {
                        Label("立即恢复守护", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                } else {
                    HStack(spacing: 8) {
                        Button {
                            model.pauseProtection(for: 15 * 60)
                        } label: {
                            Label("暂停 15 分钟", systemImage: "pause.fill")
                        }
                        .buttonStyle(CompactButtonStyle())

                        Button {
                            model.pauseProtection(for: 60 * 60)
                        } label: {
                            Label("暂停 1 小时", systemImage: "pause.fill")
                        }
                        .buttonStyle(CompactButtonStyle())
                    }
                    .disabled(!model.protectionEnabled)
                }

                Divider().opacity(0.5)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前内存")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("窗口打开时每 10 秒刷新")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f MB", model.memoryMegabytes))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            model.memoryMegabytes < 100 ? GuardTheme.safe : GuardTheme.warning
                        )
                }
            }
        }
    }

    private var eventHistoryCard: some View {
        PanelSurface(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("守护记录")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("最多保留 40 条，不写入磁盘")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(
                        text: "\(model.protectionEvents.count) 条",
                        tint: GuardTheme.accent
                    )
                }
                .padding(15)

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                if model.protectionEvents.isEmpty {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "暂无守护记录",
                        detail: "启用后，每次配置变化和恢复结果都会显示在这里。"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.protectionEvents.prefix(10)) { event in
                            HStack(spacing: 10) {
                                Image(systemName: event.kind.symbol)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(eventTint(event.kind))
                                    .frame(width: 17)
                                Text(event.message)
                                    .font(.system(size: 10.5))
                                    .lineLimit(2)
                                Spacer()
                                Text(event.date.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            if event.id != model.protectionEvents.prefix(10).last?.id {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.045))
                                    .frame(height: 1)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        }
    }

    private var boundariesCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 10) {
                Label("保护边界", systemImage: "shield.checkered")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GuardTheme.accent)

                ParagraphNote(
                    icon: "checkmark.circle.fill",
                    text: "会恢复：明文 DNS、未绑定代理的 DoH/DoT、DNS 开关、键名拼写，以及可选 no-resolve。",
                    tint: GuardTheme.safe
                )
                ParagraphNote(
                    icon: "xmark.circle.fill",
                    text: "不会回滚整份分流规则，也不会修改订阅源；规则变化只在与 DNS 泄露相关时处理。",
                    tint: GuardTheme.warning
                )
                ParagraphNote(
                    icon: "gauge.with.dots.needle.33percent",
                    text: "60 分钟内最多自动写入 6 次；短时间反复被覆盖会进入 10 分钟限流。",
                    tint: GuardTheme.purple
                )
                ParagraphNote(
                    icon: "power.circle.fill",
                    text: "守护仅在应用运行时生效；需要持续守护时开启“登录时启动”。",
                    tint: GuardTheme.accent
                )
            }
        }
    }

    private func eventTint(_ kind: ProtectionEvent.Kind) -> Color {
        switch kind {
        case .armed, .repaired, .resumed: GuardTheme.safe
        case .change: GuardTheme.accent
        case .repairFailed: GuardTheme.danger
        case .paused: GuardTheme.warning
        case .disabled: GuardTheme.idle
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "尚未" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
