import Foundation

public struct ClashRuleOptions: Sendable {
    public var proxyGroup: String
    public var includeWhatsApp: Bool
    public var includeMeta: Bool
    public var includeLocalDirect: Bool
    public var includeLoyalsoldierProxy: Bool
    public var includeLoyalsoldierPrivate: Bool
    public var includeLoyalsoldierDirect: Bool
    public var forceProxyFallback: Bool
    public var ensureFinalMatch: Bool

    public init(
        proxyGroup: String,
        includeWhatsApp: Bool = true,
        includeMeta: Bool = false,
        includeLocalDirect: Bool = true,
        includeLoyalsoldierProxy: Bool = true,
        includeLoyalsoldierPrivate: Bool = true,
        includeLoyalsoldierDirect: Bool = false,
        forceProxyFallback: Bool = false,
        ensureFinalMatch: Bool = true
    ) {
        self.proxyGroup = proxyGroup
        self.includeWhatsApp = includeWhatsApp
        self.includeMeta = includeMeta
        self.includeLocalDirect = includeLocalDirect
        self.includeLoyalsoldierProxy = includeLoyalsoldierProxy
        self.includeLoyalsoldierPrivate = includeLoyalsoldierPrivate
        self.includeLoyalsoldierDirect = includeLoyalsoldierDirect
        self.forceProxyFallback = forceProxyFallback
        self.ensureFinalMatch = ensureFinalMatch
    }
}

public struct ClashRulePreview: Sendable {
    public let proxyGroup: String
    public let mergeFile: URL
    public let activeConfig: URL
    public let prependRules: [String]
    public let generatedSections: String
    public let mergeWillChange: Bool
    public let activeWillChange: Bool
    public let notes: [String]
}

public struct ClashRuleApplicationReport: Sendable {
    public let changedFiles: [URL]
    public let backups: [FileBackup]
    public let ruleCount: Int
    public let mergeFile: URL
    public let reloadSucceeded: Bool
    public let reloadMessage: String
    public let notes: [String]
}

public final class ClashRuleService: @unchecked Sendable {
    private let ruleMarker = ">>> DNSLeakGuard managed rules"
    private let ruleEndMarker = "<<< DNSLeakGuard managed rules"
    private let matchMarker = ">>> DNSLeakGuard final MATCH"
    private let matchEndMarker = "<<< DNSLeakGuard final MATCH"
    private let appendMarker = ">>> DNSLeakGuard append rules"
    private let appendEndMarker = "<<< DNSLeakGuard append rules"

    public init() {}

    public func preview(
        workspace: WorkspaceInfo,
        analysis: ConfigAnalysis,
        options: ClashRuleOptions
    ) throws -> ClashRulePreview {
        let plan = try makePlan(
            workspace: workspace,
            analysis: analysis,
            options: options
        )
        let mergeOriginal = try String(
            contentsOf: plan.mergeFile,
            encoding: .utf8
        )
        let activeOriginal = try String(
            contentsOf: workspace.activeConfig,
            encoding: .utf8
        )
        let activeSource = try YAMLSource(text: activeOriginal)
        let appendMatch = plan.ensureFinalMatch
            && !plan.forceProxyFallback
            && !hasMatchRule(source: activeSource)
        let mergeUpdated = try updatedMerge(
            text: mergeOriginal,
            plan: plan,
            appendMatch: appendMatch
        )
        let activeUpdated = try updatedActive(
            text: activeOriginal,
            plan: plan
        )
        return ClashRulePreview(
            proxyGroup: options.proxyGroup,
            mergeFile: plan.mergeFile,
            activeConfig: workspace.activeConfig,
            prependRules: plan.prependRules,
            generatedSections: renderPreview(
                plan: plan,
                appendMatch: appendMatch
            ),
            mergeWillChange: mergeUpdated != mergeOriginal,
            activeWillChange: activeUpdated != activeOriginal,
            notes: plan.notes
        )
    }

    public func apply(
        workspace: WorkspaceInfo,
        analysis: ConfigAnalysis,
        options: ClashRuleOptions
    ) async throws -> ClashRuleApplicationReport {
        let plan = try makePlan(
            workspace: workspace,
            analysis: analysis,
            options: options
        )
        let mergeOriginal = try String(
            contentsOf: plan.mergeFile,
            encoding: .utf8
        )
        let activeOriginal = try String(
            contentsOf: workspace.activeConfig,
            encoding: .utf8
        )
        let activeSource = try YAMLSource(text: activeOriginal)
        let appendMatch = plan.ensureFinalMatch
            && !plan.forceProxyFallback
            && !hasMatchRule(source: activeSource)
        let mergeUpdated = try updatedMerge(
            text: mergeOriginal,
            plan: plan,
            appendMatch: appendMatch
        )
        let activeUpdated = try updatedActive(
            text: activeOriginal,
            plan: plan
        )

        if activeUpdated != activeOriginal {
            let before = try ConfigScanner.analyze(text: activeOriginal)
            let after = try ConfigScanner.analyze(text: activeUpdated)
            let beforeCritical = before.findings.filter {
                $0.category == .configError && $0.severity == .critical
            }.count
            let afterCritical = after.findings.filter {
                $0.category == .configError && $0.severity == .critical
            }.count
            guard afterCritical <= beforeCritical else {
                throw ConfigParseError.unreadable(
                    "规则写入后的活动配置新增了严重错误，已取消写入。"
                )
            }
        }

        var writes: [(URL, Data)] = []
        if mergeUpdated != mergeOriginal {
            writes.append((plan.mergeFile, Data(mergeUpdated.utf8)))
        }
        if activeUpdated != activeOriginal {
            writes.append((workspace.activeConfig, Data(activeUpdated.utf8)))
        }
        let result = try writeWithBackups(writes)

        let reload: (Bool, String)
        if writes.isEmpty {
            reload = (true, "规则已是最新，无需重载。")
        } else if let socket = workspace.controlSocket {
            do {
                _ = try await UnixHTTPClient.put(
                    socketPath: socket.path,
                    path: "/configs?force=true",
                    jsonBody: ["payload": activeUpdated]
                )
                try? await Task.sleep(nanoseconds: 350_000_000)
                reload = (
                    true,
                    "活动配置已通过控制接口提交并完成重载。"
                )
            } catch {
                reload = (
                    false,
                    "文件已写入，但控制接口重载失败：\(error.localizedDescription)"
                )
            }
        } else {
            reload = (
                false,
                "文件已写入，但未找到 Clash Verge 控制接口；请重新加载配置。"
            )
        }

        var notes = plan.notes
        notes.append(
            "已同时写入当前订阅绑定的 Merge 文件与活动配置；Merge 保证下次订阅重建后仍保留，活动配置保证立即生效。"
        )
        if !reload.0 {
            notes.append("若规则尚未生效，请在 Clash Verge 中重新应用当前订阅。")
        }
        return ClashRuleApplicationReport(
            changedFiles: result.0,
            backups: result.1,
            ruleCount: plan.prependRules.count,
            mergeFile: plan.mergeFile,
            reloadSucceeded: reload.0,
            reloadMessage: reload.1,
            notes: notes
        )
    }

    private struct Plan {
        let mergeFile: URL
        let activeConfig: URL
        let proxyGroup: String
        let prependRules: [String]
        let providers: [RuleProviderDefinition]
        let ensureFinalMatch: Bool
        let forceProxyFallback: Bool
        let notes: [String]
    }

    private struct RuleProviderDefinition {
        let key: String
        let behavior: String
        let url: String
        let path: String
        let proxy: String
    }

    private func makePlan(
        workspace: WorkspaceInfo,
        analysis: ConfigAnalysis,
        options: ClashRuleOptions
    ) throws -> Plan {
        let group = options.proxyGroup.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !group.isEmpty else {
            throw ConfigParseError.unreadable("请选择一个代理组用于规则分流。")
        }
        guard analysis.proxyGroups.contains(where: { $0.name == group }) else {
            throw ConfigParseError.unreadable(
                "代理组“\(group)”已不存在，请重新扫描配置后再试。"
            )
        }
        let mergeFile = try resolveMergeFile(workspace: workspace)
        var rules: [String] = []
        var providers: [RuleProviderDefinition] = []
        var notes: [String] = []

        if options.includeLocalDirect {
            rules.append(contentsOf: [
                "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
                "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
                "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
                "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
                "IP-CIDR6,::1/128,DIRECT,no-resolve",
                "IP-CIDR6,fc00::/7,DIRECT,no-resolve",
                "IP-CIDR6,fe80::/10,DIRECT,no-resolve"
            ])
        }

        if options.includeWhatsApp {
            rules.append(contentsOf: [
                "DOMAIN-SUFFIX,whatsapp.com,\(group)",
                "DOMAIN-SUFFIX,whatsapp.net,\(group)",
                "DOMAIN-SUFFIX,whatsapp.org,\(group)",
                "DOMAIN-SUFFIX,whatsappbrand.com,\(group)",
                "DOMAIN-SUFFIX,wa.me,\(group)"
            ])
        }

        if options.includeMeta {
            rules.append(contentsOf: [
                "DOMAIN-SUFFIX,meta.com,\(group)",
                "DOMAIN-SUFFIX,facebook.com,\(group)",
                "DOMAIN-SUFFIX,fb.com,\(group)",
                "DOMAIN-SUFFIX,fbcdn.net,\(group)",
                "DOMAIN-SUFFIX,instagram.com,\(group)",
                "DOMAIN-SUFFIX,cdninstagram.com,\(group)",
                "DOMAIN-SUFFIX,messenger.com,\(group)",
                "DOMAIN-SUFFIX,threads.net,\(group)"
            ])
        }

        if options.includeLoyalsoldierPrivate {
            providers.append(
                RuleProviderDefinition(
                    key: "dnsleakguard-loyalsoldier-private",
                    behavior: "domain",
                    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt",
                    path: "./ruleset/dnsleakguard-loyalsoldier-private.yaml",
                    proxy: group
                )
            )
            rules.append(
                "RULE-SET,dnsleakguard-loyalsoldier-private,DIRECT"
            )
        }

        if options.includeLoyalsoldierDirect || options.forceProxyFallback {
            providers.append(
                RuleProviderDefinition(
                    key: "dnsleakguard-loyalsoldier-direct",
                    behavior: "domain",
                    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt",
                    path: "./ruleset/dnsleakguard-loyalsoldier-direct.yaml",
                    proxy: group
                )
            )
            rules.append(
                "RULE-SET,dnsleakguard-loyalsoldier-direct,DIRECT"
            )
        }

        if options.includeLoyalsoldierProxy {
            providers.append(
                RuleProviderDefinition(
                    key: "dnsleakguard-loyalsoldier-" + "proxy",
                    behavior: "domain",
                    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt",
                    path: "./ruleset/dnsleakguard-loyalsoldier-proxy.yaml",
                    proxy: group
                )
            )
            rules.append(
                "RULE-SET,dnsleakguard-loyalsoldier-proxy,\(group)"
            )
        }

        if options.forceProxyFallback {
            rules.append("MATCH,\(group)")
            notes.append(
                "“国内直连、其余代理”模式会在托管规则末尾加入 MATCH；它位于订阅规则之前，因此订阅中的其他分流规则将不再参与匹配。"
            )
        }

        if !rules.isEmpty {
            notes.append(
                "规则使用 Merge 的 prepend-rules，在订阅规则之前加入；不会整体替换 rules。"
            )
        }
        if options.includeLoyalsoldierProxy
            || options.includeLoyalsoldierPrivate
            || options.includeLoyalsoldierDirect
            || options.forceProxyFallback {
            notes.append(
                "Loyalsoldier/clash-rules 通过 jsDelivr release 分支加载；首次生效需要 Clash Verge 能下载规则提供器。"
            )
        }
        notes.append("不会修改 profiles/ 中当前订阅的原始 YAML。")

        return Plan(
            mergeFile: mergeFile,
            activeConfig: workspace.activeConfig,
            proxyGroup: group,
            prependRules: rules,
            providers: providers,
            ensureFinalMatch: options.ensureFinalMatch,
            forceProxyFallback: options.forceProxyFallback,
            notes: notes
        )
    }

    private func updatedMerge(
        text: String,
        plan: Plan,
        appendMatch: Bool
    ) throws -> String {
        var output = text
        output = try removeUnusedManagedProviders(
            output,
            keeping: Set(plan.providers.map(\.key))
        )
        for provider in plan.providers {
            output = try upsertProvider(output, provider: provider)
        }
        output = try upsertManagedList(
            text: output,
            key: "prepend-rules",
            marker: ruleMarker,
            endMarker: ruleEndMarker,
            values: plan.prependRules,
            prepend: true
        )
        output = try upsertManagedList(
            text: output,
            key: "append-rules",
            marker: appendMarker,
            endMarker: appendEndMarker,
            values: appendMatch ? ["MATCH,\(plan.proxyGroup)"] : [],
            prepend: false
        )
        return output
    }

    private func updatedActive(text: String, plan: Plan) throws -> String {
        var output = text
        output = try removeUnusedManagedProviders(
            output,
            keeping: Set(plan.providers.map(\.key))
        )
        for provider in plan.providers {
            output = try upsertProvider(output, provider: provider)
        }
        output = try upsertManagedList(
            text: output,
            key: "rules",
            marker: ruleMarker,
            endMarker: ruleEndMarker,
            values: plan.prependRules,
            prepend: true
        )

        output = try removeManagedList(
            text: output,
            key: "rules",
            marker: matchMarker,
            endMarker: matchEndMarker
        )
        let source = try YAMLSource(text: output)
        if plan.ensureFinalMatch, !hasMatchRule(source: source) {
            output = try upsertManagedList(
                text: output,
                key: "rules",
                marker: matchMarker,
                endMarker: matchEndMarker,
                values: ["MATCH,\(plan.proxyGroup)"],
                prepend: false
            )
        }
        return output
    }

    private func renderPreview(
        plan: Plan,
        appendMatch: Bool
    ) -> String {
        var sections: [String] = []
        if !plan.providers.isEmpty {
            var generatedProviderLines = ["rule-providers:"]
            for provider in plan.providers {
                generatedProviderLines.append(contentsOf: providerLines(
                    for: provider,
                    indent: 2
                ))
            }
            sections.append(generatedProviderLines.joined(separator: "\n"))
        }
        if !plan.prependRules.isEmpty {
            var lines = ["prepend-rules:"]
            lines.append(
                "  # \(ruleMarker)。此块由 DNS Leak Guard 更新。"
            )
            lines.append(contentsOf: plan.prependRules.map {
                "  - \(yamlQuote($0))"
            })
            lines.append("  # \(ruleEndMarker)")
            sections.append(lines.joined(separator: "\n"))
        }
        if appendMatch {
            sections.append(
                "append-rules:\n  - \(yamlQuote("MATCH,\(plan.proxyGroup)"))\n"
                    + "  # 仅在现有规则缺少 MATCH 时由活动配置补偿"
            )
        }
        return sections.joined(separator: "\n\n")
    }

    private func upsertProvider(
        _ text: String,
        provider: RuleProviderDefinition
    ) throws -> String {
        let source = try YAMLSource(text: text)
        var lines = source.lines
        guard let section = source.section(named: "rule-providers") else {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("rule-providers:")
            lines.append(contentsOf: providerLines(for: provider, indent: 2))
            return lines.joined(separator: source.lineEnding)
        }

        let headerIndex = section.lowerBound - 1
        let header = source.line(headerIndex)
        if let split = YAMLSource.splitKeyValue(header.content) {
            let inline = split.value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if inline == "{}" {
                lines[headerIndex] = String(
                    repeating: " ",
                    count: header.indent
                ) + "rule-providers:"
            } else if !inline.isEmpty {
                throw ConfigParseError.unreadable(
                    "rule-providers 使用了非空内联映射，无法安全合并。"
                )
            }
        }

        let bodyIndent = source.bodyIndent(in: section) ?? 2
        if let entryIndex = section.first(where: { index in
            let line = source.line(index)
            guard !line.isIgnorable,
                  !line.startsSequenceItem,
                  line.indent == bodyIndent,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                return false
            }
            return YAMLSource.unquote(
                split.key.trimmingCharacters(in: .whitespaces)
            ) == provider.key
        }) {
            let entry = source.line(entryIndex)
            var end = section.upperBound
            var cursor = entryIndex + 1
            while cursor < section.upperBound {
                let line = source.line(cursor)
                if !line.isIgnorable, line.indent <= entry.indent {
                    end = cursor
                    break
                }
                cursor += 1
            }
            while end > entryIndex + 1, source.line(end - 1).isIgnorable {
                end -= 1
            }
            lines.replaceSubrange(
                entryIndex..<end,
                with: providerLines(for: provider, indent: bodyIndent)
            )
        } else {
            var insertAt = section.upperBound
            while insertAt > section.lowerBound,
                  source.line(insertAt - 1).isIgnorable {
                insertAt -= 1
            }
            lines.insert(
                contentsOf: providerLines(for: provider, indent: bodyIndent),
                at: min(insertAt, lines.count)
            )
        }
        return lines.joined(separator: source.lineEnding)
    }

    private func removeUnusedManagedProviders(
        _ text: String,
        keeping: Set<String>
    ) throws -> String {
        let source = try YAMLSource(text: text)
        guard let section = source.section(named: "rule-providers") else {
            return text
        }
        var lines = source.lines
        let bodyIndent = source.bodyIndent(in: section) ?? 2
        var ranges: [Range<Int>] = []
        var index = section.lowerBound
        while index < section.upperBound {
            let line = source.line(index)
            guard !line.isIgnorable,
                  !line.startsSequenceItem,
                  line.indent == bodyIndent,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                index += 1
                continue
            }
            let key = YAMLSource.unquote(
                split.key.trimmingCharacters(in: .whitespaces)
            )
            guard key.hasPrefix("dnsleakguard-loyalsoldier-"),
                  !keeping.contains(key) else {
                index += 1
                continue
            }
            var end = index + 1
            while end < section.upperBound {
                let next = source.line(end)
                if !next.isIgnorable, next.indent <= line.indent {
                    break
                }
                end += 1
            }
            ranges.append(index..<end)
            index = end
        }
        guard !ranges.isEmpty else { return text }
        for range in ranges.reversed() {
            lines.removeSubrange(range)
        }

        let output = lines.joined(separator: source.lineEnding)
        let cleaned = try YAMLSource(text: output)
        guard let cleanedSection = cleaned.section(named: "rule-providers") else {
            return output
        }
        let hasEntry = cleanedSection.contains { lineIndex in
            let line = cleaned.line(lineIndex)
            return !line.isIgnorable
                && !line.startsSequenceItem
                && line.indent > 0
        }
        if !hasEntry {
            let headerIndex = cleanedSection.lowerBound - 1
            let header = cleaned.line(headerIndex)
            var replacement = cleaned.lines
            replacement[headerIndex] = String(
                repeating: " ",
                count: header.indent
            ) + "rule-providers: {}"
            return replacement.joined(separator: cleaned.lineEnding)
        }
        return output
    }

    private func providerLines(
        for provider: RuleProviderDefinition,
        indent: Int
    ) -> [String] {
        let pad = String(repeating: " ", count: indent)
        let child = String(repeating: " ", count: indent + 2)
        return [
            "\(pad)\(provider.key):",
            "\(child)type: http",
            "\(child)behavior: \(provider.behavior)",
            "\(child)url: \(yamlQuote(provider.url))",
            "\(child)path: \(yamlQuote(provider.path))",
            "\(child)proxy: \(yamlQuote(provider.proxy))",
            "\(child)interval: 86400"
        ]
    }

    private func upsertManagedList(
        text: String,
        key: String,
        marker: String,
        endMarker: String,
        values: [String],
        prepend: Bool
    ) throws -> String {
        let output = try removeManagedList(
            text: text,
            key: key,
            marker: marker,
            endMarker: endMarker
        )
        let source = try YAMLSource(text: output)
        var lines = source.lines

        guard let section = source.section(named: key) else {
            guard !values.isEmpty else { return output }
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("\(key):")
            lines.append(contentsOf: managedLines(
                values: values,
                indent: 2,
                marker: marker,
                endMarker: endMarker
            ))
            return lines.joined(separator: source.lineEnding)
        }

        let headerIndex = section.lowerBound - 1
        let header = source.line(headerIndex)
        if let split = YAMLSource.splitKeyValue(header.content) {
            let inline = split.value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !inline.isEmpty, inline != "[]" {
                throw ConfigParseError.unreadable(
                    "\(key) 使用了不支持的内联格式，无法安全追加规则。"
                )
            }
            if inline == "[]" {
                lines[headerIndex] = String(
                    repeating: " ",
                    count: header.indent
                ) + "\(key):"
            }
        }

        let bodyIndent = source.bodyIndent(in: section) ?? header.indent + 2
        let existingValues = Set(section.compactMap { index -> String? in
            let line = source.line(index)
            guard line.startsSequenceItem else { return nil }
            let raw = String(line.content.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return YAMLSource.unquote(raw)
        })
        let newValues = values.filter { !existingValues.contains($0) }
        guard !newValues.isEmpty else {
            return lines.joined(separator: source.lineEnding)
        }

        let insertAt: Int
        if prepend {
            insertAt = section.lowerBound
        } else {
            insertAt = section.upperBound
        }
        lines.insert(
            contentsOf: managedLines(
                values: newValues,
                indent: bodyIndent,
                marker: marker,
                endMarker: endMarker
            ),
            at: min(insertAt, lines.count)
        )
        return lines.joined(separator: source.lineEnding)
    }

    private func removeManagedList(
        text: String,
        key: String,
        marker: String,
        endMarker: String
    ) throws -> String {
        let source = try YAMLSource(text: text)
        guard let section = source.section(named: key) else { return text }
        var lines = source.lines
        var removals: [ClosedRange<Int>] = []
        var cursor = section.lowerBound
        while cursor < section.upperBound {
            let line = source.line(cursor)
            if line.content.contains(marker) {
                var end = section.upperBound - 1
                var scan = cursor + 1
                while scan < section.upperBound {
                    if source.line(scan).content.contains(endMarker) {
                        end = scan
                        break
                    }
                    scan += 1
                }
                removals.append(cursor...min(end, lines.count - 1))
                cursor = end + 1
            } else {
                cursor += 1
            }
        }
        for range in removals.reversed() {
            lines.removeSubrange(range)
        }
        return lines.joined(separator: source.lineEnding)
    }

    private func managedLines(
        values: [String],
        indent: Int,
        marker: String,
        endMarker: String
    ) -> [String] {
        let pad = String(repeating: " ", count: indent)
        var lines = ["\(pad)# \(marker). 此块由 DNS Leak Guard 更新。"]
        lines.append(contentsOf: values.map {
            "\(pad)- \(yamlQuote($0))"
        })
        lines.append("\(pad)# \(endMarker)")
        return lines
    }

    private func hasMatchRule(source: YAMLSource) -> Bool {
        guard let section = source.section(named: "rules") else {
            return false
        }
        return section.contains { index in
            let line = source.line(index)
            guard line.startsSequenceItem else { return false }
            let value = YAMLSource.unquote(
                String(line.content.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return value.uppercased().hasPrefix("MATCH,")
        }
    }

    private func resolveMergeFile(workspace: WorkspaceInfo) throws -> URL {
        guard let profilesURL = workspace.profilesFile else {
            throw ConfigParseError.unreadable(
                "未找到 profiles.yaml，无法定位当前订阅的 Merge 文件。"
            )
        }
        let text = try String(contentsOf: profilesURL, encoding: .utf8)
        let source = try YAMLSource(text: text)
        guard let currentLine = source.yamlLines.first(where: {
            $0.isTopLevelKey && YAMLSource.topLevelKey($0.content) == "current"
        }),
        let currentSplit = YAMLSource.splitKeyValue(currentLine.content) else {
            throw ConfigParseError.unreadable("profiles.yaml 中没有 current 订阅。")
        }
        let currentUID = YAMLSource.unquote(
            currentSplit.value.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let records = try profileRecords(source: source)
        let mergeUID = records.first(where: { $0.uid == currentUID })?.mergeUID

        let targetUID: String
        if let mergeUID, !mergeUID.isEmpty {
            targetUID = mergeUID
        } else if let global = records.first(where: { $0.uid == "Merge" }) {
            targetUID = global.uid
        } else {
            throw ConfigParseError.unreadable(
                "当前订阅没有绑定 Merge 文件。请先在 Clash Verge 的订阅设置中启用一个 Merge。"
            )
        }
        guard let record = records.first(where: { $0.uid == targetUID }),
              let file = record.file,
              !file.isEmpty else {
            throw ConfigParseError.unreadable("无法解析 Merge 文件名。")
        }
        let profilesDirectory = workspace.directory
            .appendingPathComponent("profiles", isDirectory: true)
        let candidates = [
            profilesDirectory.appendingPathComponent(file),
            profilesDirectory.appendingPathComponent("\(targetUID).yaml"),
            profilesDirectory.appendingPathComponent("\(targetUID).yml")
        ]
        let normalized = profilesDirectory.standardizedFileURL.path + "/"
        guard let target = candidates.first(where: {
            let path = $0.standardizedFileURL.path
            return path.hasPrefix(normalized)
                && FileManager.default.fileExists(atPath: path)
        }) else {
            throw ConfigParseError.unreadable(
                "找到当前订阅的 Merge UID，但对应文件不存在：profiles/\(file)"
            )
        }
        return target
    }

    private struct ProfileRecord {
        let uid: String
        let file: String?
        let mergeUID: String?
    }

    private func profileRecords(source: YAMLSource) throws -> [ProfileRecord] {
        guard let section = source.section(named: "items") else {
            return []
        }
        var starts: [Int] = []
        var itemIndent: Int?
        for index in section {
            let line = source.line(index)
            guard line.startsSequenceItem else { continue }
            if itemIndent == nil {
                itemIndent = line.indent
            }
            if line.indent == itemIndent {
                starts.append(index)
            }
        }
        return starts.enumerated().compactMap { offset, start in
            let end = offset + 1 < starts.count
                ? starts[offset + 1]
                : section.upperBound
            var uid: String?
            var file: String?
            var mergeUID: String?
            var optionIndent: Int?
            let baseIndent = source.line(start).indent
            let firstContent = String(source.line(start).content.dropFirst())
                .trimmingCharacters(in: .whitespaces)
            if let firstSplit = YAMLSource.splitKeyValue(firstContent) {
                let firstKey = YAMLSource.unquote(
                    firstSplit.key.trimmingCharacters(in: .whitespaces)
                )
                let firstValue = YAMLSource.unquote(
                    firstSplit.value.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                )
                if firstKey == "uid" {
                    uid = firstValue
                } else if firstKey == "file" {
                    file = firstValue
                }
            }
            var cursor = start
            while cursor < end {
                let line = source.line(cursor)
                if line.indent > baseIndent,
                   !line.isIgnorable,
                   !line.startsSequenceItem,
                   let split = YAMLSource.splitKeyValue(line.content) {
                    let key = YAMLSource.unquote(
                        split.key.trimmingCharacters(in: .whitespaces)
                    )
                    let value = YAMLSource.unquote(
                        split.value.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    )
                    if key == "option" {
                        optionIndent = line.indent
                    } else if key == "merge",
                              let optionIndent,
                              line.indent > optionIndent {
                        mergeUID = value
                    } else if key == "uid" {
                        uid = value
                    } else if key == "file" {
                        file = value
                    }
                }
                cursor += 1
            }
            guard let uid else { return nil }
            return ProfileRecord(uid: uid, file: file, mergeUID: mergeUID)
        }
    }

    private func yamlQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func writeWithBackups(
        _ writes: [(URL, Data)]
    ) throws -> ([URL], [FileBackup]) {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        var changed: [URL] = []
        var backups: [FileBackup] = []

        for (url, data) in writes {
            let backup = url
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "\(url.lastPathComponent).dnsleakguard-backup.\(stamp)"
                )
            if fileManager.fileExists(atPath: url.path) {
                var destination = backup
                if fileManager.fileExists(atPath: destination.path) {
                    destination = URL(
                        fileURLWithPath: backup.path
                            + "-"
                            + String(UUID().uuidString.prefix(6))
                    )
                }
                try fileManager.copyItem(at: url, to: destination)
                backups.append(FileBackup(original: url, backup: destination))
            }
            try data.write(to: url, options: [.atomic])
            changed.append(url)
        }
        return (changed, backups)
    }
}
