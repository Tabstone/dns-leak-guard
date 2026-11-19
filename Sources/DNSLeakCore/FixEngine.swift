import Foundation

public enum ConfigFixer {
    public struct Result: Sendable {
        public let text: String
        public let changeCount: Int
        public let appliedActions: [FixOptionType]
        public let notes: [String]

        public init(
            text: String,
            changeCount: Int,
            appliedActions: [FixOptionType],
            notes: [String]
        ) {
            self.text = text
            self.changeCount = changeCount
            self.appliedActions = appliedActions
            self.notes = notes
        }
    }

    public static func preview(
        text: String,
        selection: FixSelection,
        proxyGroup: String?,
        includeRuleFixes: Bool
    ) throws -> Result {
        try apply(
            text: text,
            selection: selection,
            proxyGroup: proxyGroup,
            includeRuleFixes: includeRuleFixes
        )
    }

    public static func apply(
        text: String,
        selection: FixSelection,
        proxyGroup: String?,
        includeRuleFixes: Bool
    ) throws -> Result {
        var working = text
        var notes: [String] = []
        var actions: Set<FixOptionType> = []
        var totalChanges = 0

        if selection.enableMihomoDNS {
            let phase = try ensureDNSEnabled(text: working, group: proxyGroup)
            working = phase.text
            totalChanges += phase.changes
            if phase.changes > 0 {
                actions.insert(.enableMihomoDNS)
            }
        }

        if selection.fixDNSKeyTypos {
            let phase = try fixDNSKeys(text: working)
            working = phase.text
            totalChanges += phase.changes
            if phase.changes > 0 {
                actions.insert(.fixDNSKeyTypos)
            }
            notes.append(contentsOf: phase.notes)
        }

        if selection.removePlaintextDNS || selection.bindDNSToProxy {
            let phase = try fixServers(
                text: working,
                removePlaintext: selection.removePlaintextDNS,
                bindToProxy: selection.bindDNSToProxy,
                group: proxyGroup
            )
            working = phase.text
            totalChanges += phase.changes
            if phase.removed > 0 {
                actions.insert(.removePlaintextDNS)
            }
            if phase.bound > 0 {
                actions.insert(.bindDNSToProxy)
            }
            notes.append(contentsOf: phase.notes)
        }

        if includeRuleFixes, selection.addNoResolve {
            let phase = try addNoResolve(text: working)
            working = phase.text
            totalChanges += phase.changes
            if phase.changes > 0 {
                actions.insert(.addNoResolve)
            }
            notes.append(contentsOf: phase.notes)
        }

        if !selection.bindDNSToProxy, proxyGroup == nil {
            notes.append("未选择代理组，跳过 DNS 代理绑定。")
        }
        if selection.addNoResolve {
            notes.append("no-resolve 可能改变 GEOIP 对域名请求的分流结果；已按您的勾选应用。")
        }
        return Result(
            text: working,
            changeCount: totalChanges,
            appliedActions: FixOptionType.allCases.filter(actions.contains),
            notes: Array(NSOrderedSet(array: notes)) as? [String] ?? notes
        )
    }

    private struct PhaseResult {
        let text: String
        let changes: Int
        let removed: Int
        let bound: Int
        let notes: [String]

        init(
            text: String,
            changes: Int = 0,
            removed: Int = 0,
            bound: Int = 0,
            notes: [String] = []
        ) {
            self.text = text
            self.changes = changes
            self.removed = removed
            self.bound = bound
            self.notes = notes
        }
    }

    private static func ensureDNSEnabled(text: String, group: String?) throws -> PhaseResult {
        let source = try YAMLSource(text: text)
        guard let range = source.section(named: "dns") else {
            let safeServer = "https://1.1.1.1/dns-query" + proxySuffix(group)
            var lines = source.lines
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append(contentsOf: [
                "dns:",
                "  enable: true",
                "  enhanced-mode: fake-ip",
                "  nameserver:",
                "    - \(safeServer)",
                "  proxy-server-nameserver:",
                "    - https://223.5.5.5/dns-query"
            ])
            return PhaseResult(
                text: lines.joined(separator: source.lineEnding),
                changes: 7,
                notes: ["原配置没有 dns 段，已生成最小 fake-ip 加密 DNS 配置。"]
            )
        }

        let dnsLine = range.lowerBound - 1
        let bodyIndent = source.bodyIndent(in: range) ?? (source.line(dnsLine).indent + 2)
        var entries: [DNSMapEntry] = []
        for index in range {
            let line = source.line(index)
            guard !line.isIgnorable,
                  line.indent == bodyIndent,
                  !line.startsSequenceItem,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                continue
            }
            let key = YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces))
            let ns = line.raw as NSString
            let keyRange = ns.range(
                of: split.key,
                options: [],
                range: NSRange(location: line.indent, length: ns.length - line.indent)
            )
            entries.append(
                DNSMapEntry(
                    key: key,
                    line: index,
                    keyStart: keyRange.location == NSNotFound ? line.indent : keyRange.location,
                    keyEnd: keyRange.location == NSNotFound
                        ? line.indent + split.key.utf16.count
                        : keyRange.location + keyRange.length,
                    value: split.value.isEmpty ? nil : split.value
                )
            )
        }

        if let enable = entries.first(where: { $0.key == "enable" }) {
            if YAMLSource.boolean(enable.value) == true {
                return PhaseResult(text: text)
            }
            let line = source.line(enable.line)
            guard let split = YAMLSource.splitKeyValue(line.content),
                  let token = source.token(
                    from: enable.line,
                    startingAt: line.indent + line.content.count - split.value.count
                  ) else {
                return PhaseResult(text: text, notes: ["未能定位 dns.enable 的值，跳过启用修复。"])
            }
            var lines = source.lines
            lines[enable.line] = replaceToken(
                in: lines[enable.line],
                start: token.start,
                end: token.end,
                value: "true",
                quote: nil
            )
            return PhaseResult(
                text: lines.joined(separator: source.lineEnding),
                changes: 1
            )
        }

        var lines = source.lines
        let indent = String(repeating: " ", count: bodyIndent)
        lines.insert("\(indent)enable: true", at: min(dnsLine + 1, lines.count))
        return PhaseResult(
            text: lines.joined(separator: source.lineEnding),
            changes: 1
        )
    }

    private static func fixDNSKeys(text: String) throws -> PhaseResult {
        let source = try YAMLSource(text: text)
        guard let range = source.section(named: "dns"),
              let bodyIndent = source.bodyIndent(in: range) else {
            return PhaseResult(text: text)
        }

        var entries: [DNSMapEntry] = []
        for index in range {
            let line = source.line(index)
            guard !line.isIgnorable,
                  line.indent == bodyIndent,
                  !line.startsSequenceItem,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                continue
            }
            let key = YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces))
            let ns = line.raw as NSString
            let found = ns.range(
                of: split.key,
                options: [],
                range: NSRange(location: line.indent, length: ns.length - line.indent)
            )
            entries.append(
                DNSMapEntry(
                    key: key,
                    line: index,
                    keyStart: found.location == NSNotFound ? line.indent : found.location,
                    keyEnd: found.location == NSNotFound
                        ? line.indent + split.key.utf16.count
                        : found.location + found.length,
                    value: split.value
                )
            )
        }

        let existing = Set(entries.map(\.key))
        var lines = source.lines
        var changes = 0
        var notes: [String] = []
        for entry in entries where !ConfigParser.dnsKeys.contains(entry.key) {
            guard let suggestion = ConfigScanner.closestKey(entry.key, candidates: ConfigParser.dnsKeys),
                  !existing.contains(suggestion) else {
                continue
            }
            let originalLine = lines[entry.line]
            let ns = originalLine as NSString
            guard entry.keyStart >= 0, entry.keyEnd <= ns.length else { continue }
            let originalKey = ns.substring(
                with: NSRange(location: entry.keyStart, length: entry.keyEnd - entry.keyStart)
            )
            let quote: Character?
            if originalKey.first == "'" || originalKey.first == "\"" {
                quote = originalKey.first
            } else {
                quote = nil
            }
            lines[entry.line] = replaceToken(
                in: originalLine,
                start: entry.keyStart,
                end: entry.keyEnd,
                value: suggestion,
                quote: quote
            )
            changes += 1
            notes.append("将 dns.\(entry.key) 修正为 dns.\(suggestion)。")
        }
        return PhaseResult(
            text: lines.joined(separator: source.lineEnding),
            changes: changes,
            notes: notes
        )
    }

    private static func fixServers(
        text: String,
        removePlaintext: Bool,
        bindToProxy: Bool,
        group: String?
    ) throws -> PhaseResult {
        let parsed = try ConfigParser.parse(text: text)
        guard let dns = parsed.dns else {
            return PhaseResult(text: text)
        }
        let source = try YAMLSource(text: text)
        var lines = source.lines
        var changes = 0
        var removed = 0
        var bound = 0
        var notes: [String] = []

        let removableLists: Set<DNSListKind> = [
            .nameserver, .fallback, .proxyServerNameserver, .policy
        ]
        let servers = uniqueServers(
            dns.nameserver + dns.fallback + dns.proxyServerNameserver + dns.policy.flatMap(\.servers)
        )
        var finalValueByEntry: [ServerKey: String] = [:]
        var removeEntries: Set<ServerKey> = []

        for server in servers {
            guard let list = server.list else { continue }
            let parsedServer = ServerParser.parse(server.raw)
            var value = server.raw
            if removePlaintext,
               removableLists.contains(list),
               parsedServer.grade == .plain {
                removeEntries.insert(ServerKey(server))
                continue
            }
            if bindToProxy,
               let group,
               [.nameserver, .fallback, .policy].contains(list),
               parsedServer.grade == .encryptedCN || parsedServer.grade == .encryptedForeign,
               parsedServer.proxyName == nil {
                value = bind(server: value, to: group)
                if value != server.raw {
                    finalValueByEntry[ServerKey(server)] = value
                    bound += 1
                }
            }
        }

        let groups = Dictionary(grouping: servers) { server -> String in
            "\(server.list?.rawValue ?? "")|\(server.policyKey ?? "")"
        }
        for (_, listServers) in groups {
            guard let sample = listServers.first,
                  let list = sample.list,
                  removableLists.contains(list) else {
                continue
            }
            let willRemain = listServers.filter { !removeEntries.contains(ServerKey($0)) }
            let finalRemain = willRemain.filter {
                finalValueByEntry[ServerKey($0)] != nil || !removeEntries.contains(ServerKey($0))
            }
            if finalRemain.isEmpty,
               let replacementEntry = listServers.first(where: {
                   removeEntries.contains(ServerKey($0))
               }) ?? listServers.first {
                removeEntries.remove(ServerKey(replacementEntry))
                finalValueByEntry[ServerKey(replacementEntry)] = safeServer(
                    for: list,
                    group: bindToProxy ? group : nil
                )
                notes.append("DNS 列表原本会被删空，已保留一个加密 DoH 作为安全回退。")
            }
        }

        let entriesByLine = Dictionary(grouping: servers, by: \.line)
        for (lineIndex, lineEntries) in entriesByLine {
            let rawLine = lines[lineIndex]
            let ns = rawLine as NSString
            let isFlow = ns.range(of: "[").location != NSNotFound
                && ns.range(of: "]").location != NSNotFound
            if isFlow {
                let values = lineEntries.compactMap { entry -> String? in
                    if removeEntries.contains(ServerKey(entry)) {
                        removed += 1
                        return nil
                    }
                    return finalValueByEntry[ServerKey(entry)] ?? entry.raw
                }
                guard !values.isEmpty else { continue }
                let open = ns.range(of: "[").location
                let close = ns.range(of: "]", options: .backwards).location
                guard open != NSNotFound, close != NSNotFound, open < close else { continue }
                let existing = ns.substring(
                    with: NSRange(location: open + 1, length: close - open - 1)
                )
                if values != parseExistingFlowValues(existing) {
                    lines[lineIndex] = ns.replacingCharacters(
                        in: NSRange(location: open + 1, length: close - open - 1),
                        with: values.joined(separator: ", ")
                    )
                    changes += 1
                }
                continue
            }

            guard lineEntries.count == 1, let entry = lineEntries.first else {
                notes.append("第 \(lineIndex + 1) 行包含复合 YAML 写法，已保守跳过自动改写。")
                continue
            }
            if removeEntries.contains(ServerKey(entry)) {
                lines[lineIndex] = ""
                removed += 1
                changes += 1
            } else if let value = finalValueByEntry[ServerKey(entry)], value != entry.raw {
                lines[lineIndex] = replaceToken(
                    in: rawLine,
                    start: entry.tokenStart,
                    end: entry.tokenEnd,
                    value: value,
                    quote: entry.quote
                )
                changes += 1
            }
        }

        if removePlaintext {
            let ignoredPlain = uniqueServers(dns.defaultNameserver + dns.directNameserver).filter {
                ServerParser.parse($0.raw).grade == .plain
            }
            if !ignoredPlain.isEmpty {
                notes.append("default-nameserver / direct-nameserver 的明文项保留：它们承担启动解析或明确的直连解析职责。")
            }
        }
        return PhaseResult(
            text: lines.joined(separator: source.lineEnding),
            changes: changes,
            removed: removed,
            bound: bound,
            notes: notes
        )
    }

    private static func addNoResolve(text: String) throws -> PhaseResult {
        let analysis = try ConfigScanner.analyze(text: text)
        let lineNumbers = Set(
            analysis.findings
                .filter { $0.fix == .addNoResolve }
                .flatMap(\.fixableLines)
        )
        guard !lineNumbers.isEmpty else {
            return PhaseResult(text: text, notes: ["没有可安全自动添加 no-resolve 的简单 IP 规则。"])
        }
        let parsed = try ConfigParser.parse(text: text)
        let source = try YAMLSource(text: text)
        var lines = source.lines
        var byLine: [Int: ParsedRule] = [:]
        for rule in parsed.rules where lineNumbers.contains(rule.line) {
            byLine[rule.line] = rule
        }

        var changes = 0
        var notes: [String] = []
        for (line, rule) in byLine {
            guard rule.tokenStart < rule.tokenEnd else {
                notes.append("规则 \(rule.raw) 的 YAML 写法无法安全定位，已跳过。")
                continue
            }
            let value = rule.raw + ",no-resolve"
            lines[line] = replaceToken(
                in: lines[line],
                start: rule.tokenStart,
                end: rule.tokenEnd,
                value: value,
                quote: rule.quote
            )
            changes += 1
        }
        return PhaseResult(
            text: lines.joined(separator: source.lineEnding),
            changes: changes,
            notes: notes
        )
    }

    private struct ServerKey: Hashable {
        let line: Int
        let start: Int
        let end: Int

        init(_ entry: DNSServerEntry) {
            self.line = entry.line
            self.start = entry.tokenStart
            self.end = entry.tokenEnd
        }
    }

    private static func uniqueServers(_ servers: [DNSServerEntry]) -> [DNSServerEntry] {
        var seen: Set<ServerKey> = []
        return servers.filter { seen.insert(ServerKey($0)).inserted }
    }

    private static func bind(server: String, to group: String) -> String {
        let parsed = ServerParser.parse(server)
        guard parsed.proxyName == nil else { return server }
        guard ["https", "tls", "quic", "h3"].contains(parsed.scheme) else { return server }
        let pieces = server.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let base = String(pieces[0])
        let existing = pieces.count > 1 ? String(pieces[1]) : ""
        let encodedGroup = encodeProxyName(group)
        if existing.isEmpty {
            return "\(base)#\(encodedGroup)"
        }
        return "\(base)#\(encodedGroup)&\(existing)"
    }

    private static func proxySuffix(_ group: String?) -> String {
        guard let group, !group.isEmpty else { return "" }
        return "#" + encodeProxyName(group)
    }

    private static func encodeProxyName(_ group: String) -> String {
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.remove(charactersIn: "&#?")
        return group.addingPercentEncoding(withAllowedCharacters: allowed) ?? group
    }

    private static func safeServer(for list: DNSListKind, group: String?) -> String {
        if list == .proxyServerNameserver {
            return "https://223.5.5.5/dns-query"
        }
        return "https://1.1.1.1/dns-query" + proxySuffix(group)
    }

    private static func replaceToken(
        in line: String,
        start: Int,
        end: Int,
        value: String,
        quote: Character?
    ) -> String {
        let ns = line as NSString
        guard start >= 0, end >= start, end <= ns.length else { return line }
        let escaped: String
        if quote == "\"" {
            escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        } else if quote == "'" {
            escaped = value.replacingOccurrences(of: "'", with: "''")
        } else {
            escaped = value
        }
        let replacement = quote.map { "\($0)\(escaped)\($0)" } ?? escaped
        return ns.replacingCharacters(
            in: NSRange(location: start, length: end - start),
            with: replacement
        )
    }

    private static func parseExistingFlowValues(_ raw: String) -> [String] {
        raw.split(separator: ",").map {
            YAMLSource.unquote($0.trimmingCharacters(in: .whitespaces))
        }
    }
}
