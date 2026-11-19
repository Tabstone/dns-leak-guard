import AppKit
import DNSLeakCore
import SwiftUI

struct LiveTrafficView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var state = LiveTrafficUIState()

    private var filteredDomains: [ClashLiveDomain] {
        let query = state.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = model.liveDomains.filter { domain in
            guard !query.isEmpty else { return true }
            return [
                domain.host,
                domain.ruleType,
                domain.rulePayload,
                domain.exitName ?? "",
                domain.nodeName ?? "",
                domain.processNames.joined(separator: " ")
            ].contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
        switch state.sortMode {
        case .recent:
            return rows.sorted {
                if $0.activeConnections != $1.activeConnections {
                    return $0.activeConnections > $1.activeConnections
                }
                return $0.lastSeen > $1.lastSeen
            }
        case .traffic:
            return rows.sorted {
                ($0.download + $0.upload) > ($1.download + $1.upload)
            }
        case .rate:
            return rows.sorted {
                ($0.downloadRate + $0.uploadRate)
                    > ($1.downloadRate + $1.uploadRate)
            }
        case .name:
            return rows.sorted {
                $0.host.localizedStandardCompare($1.host) == .orderedAscending
            }
        }
    }

    private var activeConnectionCount: Int {
        model.liveDomains.reduce(0) { $0 + $1.activeConnections }
    }

    private var totalDownload: Int64 {
        model.liveDomains.reduce(0) { $0 + $1.download }
    }

    private var totalUpload: Int64 {
        model.liveDomains.reduce(0) { $0 + $1.upload }
    }

    var body: some View {
        VStack(spacing: 14) {
            if let error = model.errorMessage {
                ErrorBannerView(message: error)
            }

            streamHeader
            if let message = model.liveActionMessage {
                actionNotice(message)
            }
            summaryStrip
            upstreamCard

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 12) {
                    liveCard
                    ruleDraftCard
                }
                .frame(maxWidth: .infinity)

                targetPanel
                    .frame(width: 292)
            }

            providerCard
        }
        .task {
            model.startLiveTrafficMonitor()
            await model.loadRuleDraft()
        }
        .onDisappear {
            model.stopLiveTrafficMonitor()
        }
        .sheet(
            isPresented: Binding(
                get: { state.managedGroupName != nil },
                set: { visible in
                    if !visible { state.managedGroupName = nil }
                }
            )
        ) {
            if let name = state.managedGroupName {
                ProxyGroupManagementView(groupName: name) {
                    state.managedGroupName = nil
                }
                .environmentObject(model)
            }
        }
    }

    private func actionNotice(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GuardTheme.safe)
            Text(message)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
            Spacer()
            Button {
                model.liveActionMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("关闭提示")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            GuardTheme.safe.opacity(0.075),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private var streamHeader: some View {
        HStack(spacing: 10) {
            Label("实时链路", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 14, weight: .bold, design: .rounded))

            StatusBadge(
                text: model.liveTrafficConnected
                    ? (model.liveTrafficStreaming ? "STREAM 运行中" : "已暂停")
                    : (model.liveTrafficStreaming ? "等待控制器" : "已停止"),
                tint: model.liveTrafficConnected
                    ? GuardTheme.safe
                    : GuardTheme.warning,
                icon: model.liveTrafficStreaming ? "waveform.path.ecg" : "pause.fill"
            )

            if let date = model.liveTrafficUpdatedAt {
                Text("更新于 \(date.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let error = model.liveTrafficError, model.liveTrafficStreaming {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(GuardTheme.warning)
                    .lineLimit(1)
                    .frame(maxWidth: 260, alignment: .trailing)
            }

            Button {
                if model.liveTrafficStreaming {
                    model.stopLiveTrafficMonitor()
                } else {
                    model.startLiveTrafficMonitor()
                }
            } label: {
                Label(
                    model.liveTrafficStreaming ? "暂停" : "继续",
                    systemImage: model.liveTrafficStreaming ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(CompactButtonStyle())

            Button {
                Task { await model.refreshLiveControllerNow() }
            } label: {
                Label("刷新控制器", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CompactButtonStyle())
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            trafficMetric(
                title: "活跃连接",
                value: "\(activeConnectionCount)",
                detail: "\(model.liveDomains.filter { $0.activeConnections > 0 }.count) 个目标",
                symbol: "bolt.horizontal.circle.fill",
                tint: GuardTheme.accent
            )
            trafficMetric(
                title: "下载",
                value: formatBytes(totalDownload),
                detail: "本次会话累计",
                symbol: "arrow.down.circle.fill",
                tint: GuardTheme.safe
            )
            trafficMetric(
                title: "上传",
                value: formatBytes(totalUpload),
                detail: "本次会话累计",
                symbol: "arrow.up.circle.fill",
                tint: GuardTheme.purple
            )
            trafficMetric(
                title: "控制器规则",
                value: "\(model.liveControllerRules.count)",
                detail: "\(model.liveProxyGroups.count) 个出口组",
                symbol: "list.number",
                tint: GuardTheme.warning
            )
        }
    }

    private func trafficMetric(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("\(title) · \(detail)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var liveCard: some View {
        PanelSurface(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("访问路径")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        Text("域名 → 命中规则 → 出口 → 节点；将域名拖到右侧生成规则。")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("域名、规则、进程", text: $state.search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 9)
                        .frame(width: 190, height: 27)
                        .background(
                            Color.primary.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    Picker("排序", selection: $state.sortMode) {
                        ForEach(TrafficSortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 90)
                }
                .padding(14)

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                if filteredDomains.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(model.liveTrafficStreaming ? "等待新的连接活动" : "实时流已暂停")
                            .font(.system(size: 12, weight: .semibold))
                        Text("打开浏览器或其他联网应用后，连接会出现在这里。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 190)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredDomains) { domain in
                                LiveDomainRow(
                                    domain: domain,
                                    proxyGroups: model.liveProxyGroups.map(\.name),
                                    isExpanded: state.expanded.contains(domain.id),
                                    onToggle: {
                                        if state.expanded.contains(domain.id) {
                                            state.expanded.remove(domain.id)
                                        } else {
                                            state.expanded.insert(domain.id)
                                        }
                                    },
                                    onGenerate: { target in
                                        _ = model.addRuleFromLiveHost(
                                            domain.host,
                                            target: target
                                        )
                                    }
                                )
                                Rectangle()
                                    .fill(Color.primary.opacity(0.045))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .frame(minHeight: 280, maxHeight: 420)
                }
            }
        }
    }

    private var targetPanel: some View {
        PanelSurface(padding: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("拖放出口", systemImage: "scope")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    Text("拖动只生成待应用草稿，不会自动写入；随后点“应用到 Clash”才会备份、写入并重载。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 7) {
                        TargetDropCard(
                            name: "DIRECT",
                            detail: "直接访问，不经过代理",
                            type: "内置",
                            symbol: "arrow.right.circle.fill",
                            tint: GuardTheme.safe,
                            isSelected: false,
                            canManage: false,
                            onDropHost: { host in
                                model.addRuleFromLiveHost(host, target: "DIRECT")
                            },
                            onManage: nil
                        )
                        TargetDropCard(
                            name: "REJECT",
                            detail: "拒绝命中此目标的连接",
                            type: "内置",
                            symbol: "nosign",
                            tint: GuardTheme.danger,
                            isSelected: false,
                            canManage: false,
                            onDropHost: { host in
                                model.addRuleFromLiveHost(host, target: "REJECT")
                            },
                            onManage: nil
                        )
                        ForEach(model.liveProxyGroups) { group in
                            TargetDropCard(
                                name: group.name,
                                detail: group.selected.map { "当前：\($0)" }
                                    ?? "\(group.memberCount) 个成员",
                                type: proxyTypeLabel(group.type),
                                symbol: "point.3.filled.connected.trianglepath.dotted",
                                tint: GuardTheme.purple,
                                isSelected: group.selected != nil,
                                canManage: true,
                                onDropHost: { host in
                                    model.addRuleFromLiveHost(host, target: group.name)
                                },
                                onManage: {
                                    state.managedGroupName = group.name
                                }
                            )
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 280, maxHeight: 500)
            }
        }
    }

    private var ruleDraftCard: some View {
        PanelSurface(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("完整规则草稿")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        Text("拖拽只修改草稿；点“应用到 Clash”才会备份、写入并重载。")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(
                        text: ruleDraftStatus,
                        tint: ruleDraftStatusTint,
                        icon: ruleDraftStatusSymbol
                    )
                }
                .padding(14)

                HStack(spacing: 8) {
                    TextField("搜索规则类型、内容或出口", text: $state.ruleSearch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 9)
                        .frame(height: 27)
                        .background(
                            Color.primary.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    Button("重新载入") {
                        Task { await model.restoreRuleDraft() }
                    }
                    .buttonStyle(CompactButtonStyle())
                    Button("校验") {
                        Task { _ = await model.validateRuleDraft() }
                    }
                    .buttonStyle(CompactButtonStyle())
                    Button("导出 YAML") {
                        Task { await model.exportRuleDraft() }
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    Button {
                        Task { await model.applyRuleDraft() }
                    } label: {
                        Label("应用到 Clash", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(model.ruleDraftDocument == nil || model.isBusy)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 11)

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)

                if model.ruleDraftIsLoading {
                    ProgressView("正在读取完整规则…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else if model.ruleDraftRules.isEmpty {
                    Text("尚未载入规则。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else if filteredDraftRules.isEmpty {
                    Text("没有匹配“\(state.ruleSearch)”的规则。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ruleList
                }

                if !model.ruleDraftIssues.isEmpty {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(model.ruleDraftIssues.prefix(5)) { issue in
                            HStack(alignment: .top, spacing: 7) {
                                Image(
                                    systemName: issue.isError
                                        ? "xmark.octagon.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(
                                    issue.isError
                                        ? GuardTheme.danger
                                        : GuardTheme.warning
                                )
                                .padding(.top, 1)
                                Text(issue.message)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                        }
                    }
                    .padding(11)
                }

                if let message = model.ruleDraftExportMessage {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                    Text(message)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                }

                if let report = model.ruleEditorReport {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                    HStack(spacing: 9) {
                        StatusBadge(
                            text: report.reloadSucceeded ? "已应用" : "已写入",
                            tint: report.reloadSucceeded
                                ? GuardTheme.safe
                                : GuardTheme.warning
                        )
                        Text(report.reloadMessage)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        if let backup = report.backup {
                            Text("备份：\(backup.lastPathComponent)")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(11)
                }
            }
        }
    }

    private var ruleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredDraftRules) { item in
                    EditableRuleRow(
                        index: item.index,
                        rule: item.rule,
                        onMoveUp: {
                            model.moveRuleDraftRule(item.rule.id, offset: -1)
                        },
                        onMoveDown: {
                            model.moveRuleDraftRule(item.rule.id, offset: 1)
                        },
                        onDelete: {
                            model.deleteRuleDraftRule(item.rule.id)
                        },
                        onDropBefore: { droppedID in
                            model.moveRuleDraftRule(droppedID, before: item.rule.id)
                        }
                    )
                    Rectangle()
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 1)
                }
            }
        }
        .frame(minHeight: 300, maxHeight: 430)
    }

    private var filteredDraftRules: [IndexedDraftRule] {
        let query = state.ruleSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.ruleDraftRules.enumerated().compactMap { index, rule in
            guard query.isEmpty
                    || rule.type.localizedCaseInsensitiveContains(query)
                    || rule.payload.localizedCaseInsensitiveContains(query)
                    || rule.target.localizedCaseInsensitiveContains(query) else {
                return nil
            }
            return IndexedDraftRule(index: index, rule: rule)
        }
    }

    private var ruleDraftStatus: String {
        if model.ruleDraftDocument == nil { return "未载入" }
        if model.ruleDraftIsDirty {
            if model.ruleDraftIsValidated {
                return model.ruleDraftIssues.contains(where: \.isError)
                    ? "有错误"
                    : "已校验 · 待应用"
            }
            return "草稿未应用"
        }
        return "与活动配置一致"
    }

    private var ruleDraftStatusTint: Color {
        if model.ruleDraftDocument == nil { return GuardTheme.idle }
        if model.ruleDraftIsValidated {
            return model.ruleDraftIssues.contains(where: \.isError)
                ? GuardTheme.danger
                : GuardTheme.safe
        }
        return model.ruleDraftIsDirty ? GuardTheme.warning : GuardTheme.safe
    }

    private var ruleDraftStatusSymbol: String {
        if model.ruleDraftIsValidated,
           model.ruleDraftIssues.contains(where: \.isError) {
            return "xmark.octagon.fill"
        }
        if model.ruleDraftIsValidated {
            return "checkmark.seal.fill"
        }
        return model.ruleDraftIsDirty
            ? "square.and.pencil"
            : "checkmark.circle"
    }

    private var upstreamCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Label(
                        "规则仓库 · Loyalsoldier/clash-rules",
                        systemImage: "shippingbox.and.arrow.backward.fill"
                    )
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    if let snapshot = model.upstreamSnapshot {
                        StatusBadge(
                            text: "release@\(snapshot.shortCommitSHA)",
                            tint: GuardTheme.accent,
                            icon: "arrow.triangle.2.circlepath"
                        )
                    }
                    if model.upstreamIsLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Button("打开仓库") {
                        model.openLoyalsoldierRuleRepository()
                    }
                    .buttonStyle(CompactButtonStyle())
                    Button("检查更新") {
                        Task { await model.checkLoyalsoldierRuleRepository() }
                    }
                    .buttonStyle(CompactButtonStyle())
                    .disabled(model.upstreamIsLoading)
                    Button("拉取并刷新") {
                        Task { await model.pullLoyalsoldierRuleUpdates() }
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(model.upstreamIsLoading)
                }

                Text("这是实际的 Clash RULE-SET 规则源。工具读取 release 分支的 private/direct/proxy，拉取后保存规则文件，并立即使当前 mihomo 提供器重新下载。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let snapshot = model.upstreamSnapshot {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.repositoryName)
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            Text(
                                "\(snapshot.stars) stars · \(snapshot.releaseBranch)@\(snapshot.shortCommitSHA)"
                            )
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            Text(snapshot.description)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(
                                "规则构建：\(formatUpstreamDate(snapshot.releaseCommitDate))"
                            )
                            .font(.system(size: 9.5, weight: .medium))
                            Text(snapshot.releaseCommitMessage)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    VStack(spacing: 0) {
                        upstreamRuleRow(
                            file: "private.txt",
                            upstreamCount: snapshot.privateRuleCount,
                            provider: liveRuleProvider(
                                containing: "loyalsoldier-private"
                            ),
                            tint: GuardTheme.safe
                        )
                        Rectangle()
                            .fill(Color.primary.opacity(0.045))
                            .frame(height: 1)
                        upstreamRuleRow(
                            file: "direct.txt",
                            upstreamCount: snapshot.directRuleCount,
                            provider: liveRuleProvider(
                                containing: "loyalsoldier-direct"
                            ),
                            tint: GuardTheme.warning
                        )
                        Rectangle()
                            .fill(Color.primary.opacity(0.045))
                            .frame(height: 1)
                        upstreamRuleRow(
                            file: "proxy.txt",
                            upstreamCount: snapshot.proxyRuleCount,
                            provider: liveRuleProvider(
                                containing: "loyalsoldier-proxy"
                            ),
                            tint: GuardTheme.accent
                        )
                    }
                    .padding(.horizontal, 10)
                    .background(
                        Color.primary.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                    HStack(spacing: 9) {
                        Button("打开本地规则缓存") {
                            model.openLoyalsoldierRuleCache()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 9.5))
                        Spacer()
                        if let syncedAt = model.upstreamSyncedAt {
                            Text(
                                "上次同步：\(syncedAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Text("尚未读取规则仓库。点击“检查更新”比较 release 提交；点击“拉取并刷新”保存三类规则并刷新当前内核。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if let message = model.upstreamStatusMessage {
                    Text(message)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            Color.primary.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
            }
        }
    }

    private func liveRuleProvider(
        containing fragment: String
    ) -> ClashLiveRuleProvider? {
        model.liveRuleProviders.first {
            $0.name.localizedCaseInsensitiveContains(fragment)
        }
    }

    private func upstreamRuleRow(
        file: String,
        upstreamCount: Int,
        provider: ClashLiveRuleProvider?,
        tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(provider == nil ? Color.secondary.opacity(0.35) : tint)
                .frame(width: 6, height: 6)
            Text(file)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .frame(width: 82, alignment: .leading)
            Text("上游 \(upstreamCount) 条")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Spacer()
            if let provider {
                Text("内核 \(provider.ruleCount) 条")
                    .font(.system(size: 9.5, weight: .medium))
                if let updated = provider.updatedAt {
                    Text(formatControllerDate(updated))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                StatusBadge(
                    text: provider.ruleCount == upstreamCount
                        ? "已一致"
                        : "待刷新",
                    tint: provider.ruleCount == upstreamCount
                        ? GuardTheme.safe
                        : GuardTheme.warning
                )
            } else {
                Text("当前未配置提供器")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }

    private var providerCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("规则提供器", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("Loyalsoldier 等远程规则由 mihomo 按 interval 自动刷新，也可立即拉取。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if model.liveRuleProviders.isEmpty {
                    Text("当前内核没有返回规则提供器。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.liveRuleProviders) { provider in
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GuardTheme.purple)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                Text(
                                    "\(provider.ruleCount) 条 · \(provider.vehicleType) · "
                                        + (provider.updatedAt.map(formatControllerDate) ?? "更新时间未知")
                                )
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("立即更新") {
                                Task {
                                    await model.refreshLiveRuleProvider(provider.name)
                                }
                            }
                            .buttonStyle(CompactButtonStyle())
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

private enum TrafficSortMode: String, CaseIterable, Identifiable {
    case recent
    case traffic
    case rate
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "最近活动"
        case .traffic: "累计流量"
        case .rate: "实时速率"
        case .name: "域名"
        }
    }
}

private final class LiveTrafficUIState: ObservableObject {
    @Published var search = ""
    @Published var sortMode: TrafficSortMode = .recent
    @Published var expanded = Set<String>()
    @Published var ruleSearch = ""
    @Published var managedGroupName: String?
}

private final class DropTargetState: ObservableObject {
    @Published var isTargeted = false
}

private struct IndexedDraftRule: Identifiable {
    let index: Int
    let rule: EditableClashRule

    var id: UUID { rule.id }
}

private struct LiveDomainRow: View {
    let domain: ClashLiveDomain
    let proxyGroups: [String]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onGenerate: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)

                Circle()
                    .fill(
                        domain.activeConnections > 0
                            ? GuardTheme.safe
                            : Color.secondary.opacity(0.32)
                    )
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(domain.host)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                        if domain.isIP {
                            Text("IP")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                    Text(
                        domain.processNames.isEmpty
                            ? "\(domain.activeConnections) 条活跃 · \(relativeTime(domain.lastSeen))"
                            : "\(domain.activeConnections) 条活跃 · \(domain.processNames.prefix(2).joined(separator: ", "))"
                    )
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(domain.ruleType)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(ruleTint(domain.ruleType))
                    Text(domain.rulePayload.isEmpty ? "兜底规则" : domain.rulePayload)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 105, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(domain.exitName ?? "未知出口")
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                    Text(domain.nodeName ?? "未知节点")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 126, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("↓ \(formatRate(domain.downloadRate))")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(GuardTheme.safe)
                    Text("↑ \(formatRate(domain.uploadRate))")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(GuardTheme.purple)
                }
                .frame(width: 82, alignment: .trailing)

                Text(formatBytes(domain.download + domain.upload))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .draggable(domain.host)
            .contextMenu {
                Button("生成规则 → DIRECT") {
                    onGenerate("DIRECT")
                }
                Button("生成规则 → REJECT") {
                    onGenerate("REJECT")
                }
                Divider()
                Menu("生成规则 → 代理组") {
                    ForEach(proxyGroups, id: \.self) { group in
                        Button(group) {
                            onGenerate(group)
                        }
                    }
                }
                Button("复制域名") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(domain.host, forType: .string)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        pathChip(domain.host, tint: GuardTheme.accent)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        pathChip(
                            "\(domain.ruleType) \(domain.rulePayload)",
                            tint: ruleTint(domain.ruleType)
                        )
                        ForEach(Array(domain.chains.reversed().enumerated()), id: \.offset) { index, chain in
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            pathChip(
                                chain,
                                tint: index == domain.chains.count - 1
                                    ? GuardTheme.purple
                                    : GuardTheme.accent
                            )
                        }
                        Spacer()
                    }

                    HStack(spacing: 16) {
                        fact("目标 IP", domain.destinationIP ?? "—")
                        fact("端口", domain.destinationPort ?? "—")
                        fact("网络", domain.network ?? "—")
                        fact("入口", domain.inbound ?? "—")
                        fact("连接记录", "\(domain.connectionCount)")
                        fact("累计", "↓ \(formatBytes(domain.download))  ↑ \(formatBytes(domain.upload))")
                    }

                    if domain.variants.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("命中变体")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            ForEach(domain.variants) { variant in
                                HStack(spacing: 6) {
                                    Text(variant.ruleType)
                                        .font(.system(size: 8.5, weight: .bold))
                                    Text(variant.rulePayload.isEmpty ? "兜底" : variant.rulePayload)
                                        .font(.system(size: 8.5, design: .monospaced))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 7))
                                    Text(variant.exitName ?? "—")
                                        .font(.system(size: 8.5))
                                    Text(variant.nodeName ?? "—")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(variant.count) 条")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
    }

    private func pathChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7.5))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 8.5, design: .monospaced))
                .lineLimit(1)
        }
    }
}

private final class ProxyGroupManagementState: ObservableObject {
    @Published var search = ""
}

private struct ProxyGroupManagementView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var state = ProxyGroupManagementState()

    let groupName: String
    let onClose: () -> Void

    private var group: ClashLiveProxyGroup? {
        model.liveProxyGroups.first { $0.name == groupName }
    }

    private var members: [ClashLiveProxyMember] {
        let query = state.search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return group?.members ?? [] }
        return (group?.members ?? []).filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.type.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(
                    symbol: "point.3.filled.connected.trianglepath.dotted",
                    tint: GuardTheme.purple,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("出口节点管理")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Spacer()
                Button("关闭", action: onClose)
                    .buttonStyle(CompactButtonStyle())
                    .keyboardShortcut(.escape)
            }
            .padding(18)

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)

            if let group {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        groupFact("类型", proxyTypeLabel(group.type))
                        groupFact("成员", "\(group.memberCount)")
                        groupFact("当前节点", group.selected ?? "自动选择")
                        groupFact(
                            "组延迟",
                            group.delay.map { "\($0) ms" } ?? "未测速"
                        )
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("搜索节点名称或类型", text: $state.search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        Color.primary.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                    HStack(spacing: 6) {
                        Image(
                            systemName: group.isUserSelectable
                                ? "hand.tap.fill"
                                : "wand.and.stars"
                        )
                        Text(
                            group.isUserSelectable
                                ? "切换只会改变该策略组当前选中的成员，不修改订阅或 YAML。"
                                : "该组由 mihomo 自动选择节点，成员仅可查看。"
                        )
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                }
                .padding(16)

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                if members.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("没有匹配的节点")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(members) { member in
                                memberRow(member, in: group)
                                Rectangle()
                                    .fill(Color.primary.opacity(0.045))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(GuardTheme.warning)
                    Text("出口组已不存在，请刷新控制器。")
                        .font(.system(size: 11, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 680, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func memberRow(
        _ member: ClashLiveProxyMember,
        in group: ClashLiveProxyGroup
    ) -> some View {
        let isCurrent = member.name == group.selected
        return HStack(spacing: 10) {
            Image(
                systemName: isCurrent
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isCurrent ? GuardTheme.safe : Color.secondary.opacity(0.45))
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(proxyTypeLabel(member.type))
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Text(member.delay.map { "\($0) ms" } ?? "未测速")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(delayTint(member.delay))
                .frame(width: 64, alignment: .trailing)

            Button(isCurrent ? "当前" : "切换") {
                Task {
                    await model.selectLiveProxyMember(
                        group: group.name,
                        member: member.name
                    )
                }
            }
            .buttonStyle(CompactButtonStyle())
            .frame(width: 58)
            .disabled(
                isCurrent
                    || !group.isUserSelectable
            )
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 42)
        .background(
            isCurrent
                ? GuardTheme.safe.opacity(0.055)
                : Color.clear
        )
    }

    private func groupFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func delayTint(_ delay: Int?) -> Color {
        guard let delay else { return .secondary }
        if delay < 200 { return GuardTheme.safe }
        if delay < 500 { return GuardTheme.warning }
        return GuardTheme.danger
    }
}

private struct TargetDropCard: View {
    let name: String
    let detail: String
    let type: String
    let symbol: String
    let tint: Color
    let isSelected: Bool
    let canManage: Bool
    let onDropHost: (String) -> Bool
    let onManage: (() -> Void)?

    @StateObject private var state = DropTargetState()

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    if isSelected {
                        Circle()
                            .fill(GuardTheme.safe)
                            .frame(width: 5, height: 5)
                    }
                }
                Text("\(type) · \(detail)")
                    .font(.system(size: 8.3))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if canManage, let onManage {
                Button("管理节点", action: onManage)
                    .buttonStyle(.borderless)
                    .font(.system(size: 8.5, weight: .semibold))
            }
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 46)
        .background(
            state.isTargeted
                ? tint.opacity(0.16)
                : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    state.isTargeted ? tint.opacity(0.75) : Color.primary.opacity(0.055),
                    lineWidth: state.isTargeted ? 1.5 : 1
                )
        }
        .dropDestination(for: String.self) { items, _ in
            guard let host = items.first else { return false }
            return onDropHost(host)
        } isTargeted: { targeted in
            state.isTargeted = targeted
        }
        .help("将域名拖到这里，生成指向 \(name) 的规则")
    }
}

private struct EditableRuleRow: View {
    let index: Int
    let rule: EditableClashRule
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onDropBefore: (UUID) -> Void

    @StateObject private var state = DropTargetState()

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 11)

            Text(rule.type)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(ruleTint(rule.type))
                .frame(width: 88, alignment: .leading)
                .lineLimit(1)

            Text(rule.payload.isEmpty ? "兜底规则" : rule.payload)
                .font(.system(size: 8.7, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(rule.target)
                .font(.system(size: 8.5, weight: .medium))
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)

            Text("\(rule.hitCount)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(
                    rule.hitCount > 0 ? GuardTheme.safe : Color.secondary.opacity(0.55)
                )
                .frame(width: 42, alignment: .trailing)

            HStack(spacing: 1) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .help("上移")
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .help("下移")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("删除")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 48)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 27)
        .background(
            state.isTargeted
                ? GuardTheme.accent.opacity(0.10)
                : Color.clear
        )
        .draggable(rule.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first,
                  let id = UUID(uuidString: raw) else {
                return false
            }
            onDropBefore(id)
            return true
        } isTargeted: { targeted in
            state.isTargeted = targeted
        }
    }
}

private func proxyTypeLabel(_ type: String) -> String {
    switch type {
    case "Selector", "Select": "手动选择"
    case "URLTest": "自动测速"
    case "Fallback": "故障转移"
    case "LoadBalance": "负载均衡"
    case "Relay": "链式代理"
    default: type
    }
}

private func ruleTint(_ type: String) -> Color {
    switch type {
    case "MATCH", "FINAL": GuardTheme.warning
    case "RULE-SET", "GEOSITE", "GEOIP": GuardTheme.purple
    case "REJECT", "REJECT-DROP": GuardTheme.danger
    case "DIRECT": GuardTheme.safe
    default: GuardTheme.accent
    }
}

private func formatBytes(_ bytes: Int64) -> String {
    byteFormatter.string(fromByteCount: max(0, bytes))
}

private func formatRate(_ bytes: Double) -> String {
    guard bytes > 0 else { return "0 B/s" }
    return byteFormatter.string(fromByteCount: Int64(bytes)) + "/s"
}

private let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    return formatter
}()

private func relativeTime(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 2 { return "刚刚" }
    if seconds < 60 { return "\(seconds) 秒前" }
    if seconds < 3_600 { return "\(seconds / 60) 分钟前" }
    return "\(seconds / 3_600) 小时前"
}

private func formatControllerDate(_ raw: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: raw)
        ?? ISO8601DateFormatter().date(from: raw) else {
        return raw
    }
    return date.formatted(date: .abbreviated, time: .shortened)
}

private func formatUpstreamDate(_ raw: String?) -> String {
    guard let raw else { return "未知" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: raw)
        ?? ISO8601DateFormatter().date(from: raw) else {
        return raw
    }
    return date.formatted(date: .abbreviated, time: .omitted)
}
