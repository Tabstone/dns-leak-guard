import Foundation

enum ConfigParser {
    static let dnsKeys: Set<String> = [
        "enable", "prefer-h3", "ipv6", "ipv6-timeout", "use-hosts",
        "use-system-hosts", "respect-rules", "nameserver", "fallback",
        "fallback-filter", "fallback-lazy-query", "listen",
        "listen-routing-mark", "enhanced-mode", "fake-ip-range",
        "fake-ip-range6", "fake-ip-filter", "fake-ip-filter-mode",
        "fake-ip-ttl", "default-nameserver", "cache-algorithm",
        "cache-max-size", "nameserver-policy", "proxy-server-nameserver",
        "proxy-server-nameserver-policy", "direct-nameserver",
        "direct-nameserver-follow-policy"
    ]

    static let topLevelKeys: Set<String> = [
        "port", "socks-port", "redir-port", "tproxy-port", "mixed-port",
        "ss-config", "vmess-config", "inbound-tfo", "inbound-mptcp",
        "authentication", "skip-auth-prefixes", "lan-allowed-ips",
        "lan-disallowed-ips", "allow-lan", "bind-address", "mode",
        "unified-delay", "log-level", "ipv6", "external-controller",
        "external-controller-routing-mark", "external-controller-pipe",
        "external-controller-unix", "external-controller-tls",
        "external-controller-cors", "external-ui", "external-ui-url",
        "external-ui-name", "external-doh-server", "secret",
        "interface-name", "routing-mark", "tunnels", "geo-auto-update",
        "geo-update-interval", "geodata-mode", "geodata-loader",
        "geosite-matcher", "tcp-concurrent", "find-process-mode",
        "global-client-fingerprint", "global-ua", "etag-support",
        "keep-alive-idle", "keep-alive-interval", "disable-keep-alive",
        "proxy-providers", "rule-providers", "proxies", "proxy-groups",
        "rules", "sub-rules", "listeners", "hosts", "dns", "ntp",
        "tuic-server", "iptables", "experimental", "profile", "geox-url",
        "sniffer", "tls", "clash-for-android"
    ]

    static let fallbackFilterKeys: Set<String> = [
        "geoip", "geoip-code", "ipcidr", "domain", "geosite"
    ]

    static func parse(text: String) throws -> ParsedConfig {
        let source = try YAMLSource(text: text)
        let dns = parseDNS(source)
        let groups = parseProxyGroups(source)
        let proxyNames = parseProxyNames(source)
        let providers = parseRuleProviders(source)
        let rules = parseRules(source)
        let tun = parseTun(source)
        let hasAnchors = source.lines.contains {
            $0.contains(": &") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("<<: *")
        }

        return ParsedConfig(
            text: text,
            lineEnding: source.lineEnding,
            lines: source.lines,
            dns: dns,
            groups: groups,
            proxyNames: proxyNames,
            rules: rules,
            providers: providers,
            tunEnabled: tun.enabled,
            tunDNSHijack: tun.dnsHijack,
            hasYAMLAnchors: hasAnchors
        )
    }

    private static func parseDNS(_ source: YAMLSource) -> DNSBlock? {
        guard let range = source.section(named: "dns") else { return nil }
        let startLine = range.lowerBound - 1
        guard let bodyIndent = source.bodyIndent(in: range) else {
            return DNSBlock(
                startLine: startLine,
                endLine: range.upperBound - 1,
                bodyIndent: source.line(startLine).indent + 2,
                enableLine: nil,
                enable: nil,
                mapEntries: [],
                nameserver: [],
                fallback: [],
                defaultNameserver: [],
                proxyServerNameserver: [],
                directNameserver: [],
                policy: [],
                ipv6: nil,
                respectRules: nil
            )
        }

        var mapEntries: [DNSMapEntry] = []
        for index in range {
            let line = source.line(index)
            guard !line.isIgnorable,
                  line.indent == bodyIndent,
                  !line.startsSequenceItem,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                continue
            }
            let key = YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces))
            let keyNSRange = keyRange(in: line, key: split.key)
            mapEntries.append(
                DNSMapEntry(
                    key: key,
                    line: index,
                    keyStart: keyNSRange.location,
                    keyEnd: keyNSRange.location + keyNSRange.length,
                    value: split.value.isEmpty ? nil : YAMLSource.unquote(split.value)
                )
            )
        }

        func entry(_ key: String) -> DNSMapEntry? {
            mapEntries.first { $0.key == key }
        }

        func list(_ key: String, kind: DNSListKind) -> [DNSServerEntry] {
            guard let mapEntry = entry(key) else { return [] }
            return source.parseList(keyLineIndex: mapEntry.line, sectionRange: range).map {
                DNSServerEntry(
                    raw: $0.raw,
                    list: kind,
                    line: $0.line,
                    tokenStart: $0.tokenStart,
                    tokenEnd: $0.tokenEnd,
                    quote: $0.quote,
                    policyKey: nil,
                    policySubkey: nil
                )
            }
        }

        let enableEntry = entry("enable")
        let ipv6Entry = entry("ipv6")
        let respectRulesEntry = entry("respect-rules")
        return DNSBlock(
            startLine: startLine,
            endLine: max(startLine, range.upperBound - 1),
            bodyIndent: bodyIndent,
            enableLine: enableEntry?.line,
            enable: YAMLSource.boolean(enableEntry?.value),
            mapEntries: mapEntries,
            nameserver: list("nameserver", kind: .nameserver),
            fallback: list("fallback", kind: .fallback),
            defaultNameserver: list("default-nameserver", kind: .defaultNameserver),
            proxyServerNameserver: list("proxy-server-nameserver", kind: .proxyServerNameserver),
            directNameserver: list("direct-nameserver", kind: .directNameserver),
            policy: parsePolicies(source, range: range, entry: entry("nameserver-policy")),
            ipv6: YAMLSource.boolean(ipv6Entry?.value),
            respectRules: YAMLSource.boolean(respectRulesEntry?.value)
        )
    }

    private static func parsePolicies(
        _ source: YAMLSource,
        range: Range<Int>,
        entry: DNSMapEntry?
    ) -> [PolicyEntry] {
        guard let entry else { return [] }
        if entry.value?.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" {
            return []
        }

        let keyLine = source.line(entry.line)
        var childIndent: Int?
        var index = entry.line + 1
        while index < range.upperBound {
            let line = source.line(index)
            if !line.isIgnorable && line.indent > keyLine.indent {
                childIndent = line.indent
                break
            }
            if !line.isIgnorable && line.indent <= keyLine.indent {
                break
            }
            index += 1
        }
        guard let childIndent else { return [] }

        var policies: [PolicyEntry] = []
        while index < range.upperBound {
            let line = source.line(index)
            if line.isIgnorable {
                index += 1
                continue
            }
            if line.indent < childIndent {
                break
            }
            guard line.indent == childIndent,
                  !line.startsSequenceItem,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                index += 1
                continue
            }
            let policyKey = YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces))
            var servers = source.parseList(keyLineIndex: index, sectionRange: range)
            if servers.isEmpty {
                let value = split.value.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, value != "[]" {
                    let prefixOffset = line.indent + line.content.count - value.count
                    if let token = source.token(from: index, startingAt: prefixOffset) {
                        servers = [
                            DNSServerEntry(
                                raw: token.value,
                                list: nil,
                                line: index,
                                tokenStart: token.start,
                                tokenEnd: token.end,
                                quote: token.quote,
                                policyKey: nil,
                                policySubkey: nil
                            )
                        ]
                    }
                }
            }
            let subkeys = splitPolicyKey(policyKey)
            for subkey in subkeys {
                let tagged = servers.map {
                    DNSServerEntry(
                        raw: $0.raw,
                        list: .policy,
                        line: $0.line,
                        tokenStart: $0.tokenStart,
                        tokenEnd: $0.tokenEnd,
                        quote: $0.quote,
                        policyKey: policyKey,
                        policySubkey: subkey
                    )
                }
                policies.append(
                    PolicyEntry(
                        key: subkey,
                        line: index,
                        servers: tagged
                    )
                )
            }
            index += 1
        }
        return policies
    }

    private static func parseProxyGroups(_ source: YAMLSource) -> [String: GroupDefinition] {
        guard let range = source.section(named: "proxy-groups"),
              let baseIndent = source.bodyIndent(in: range) else {
            return [:]
        }
        let itemIndices = range.filter {
            let line = source.line($0)
            return !line.isIgnorable && line.indent == baseIndent && line.startsSequenceItem
        }

        var groups: [String: GroupDefinition] = [:]
        for (position, itemStart) in itemIndices.enumerated() {
            let itemEnd = position + 1 < itemIndices.count ? itemIndices[position + 1] : range.upperBound
            let itemRange = itemStart..<itemEnd
            let firstLine = source.line(itemStart)
            let afterDash = String(firstLine.content.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            if afterDash.hasPrefix("{") {
                let flow = parseFlowMapping(afterDash)
                if let name = flow["name"] {
                    groups[name] = GroupDefinition(
                        name: name,
                        type: flow["type"] ?? "",
                        members: parseFlowArray(flow["proxies"] ?? ""),
                        includeAll: false,
                        useProviders: []
                    )
                }
                continue
            }

            var name = ""
            var type = ""
            var members: [String] = []
            var includeAll = false
            var useProviders: [String] = []

            if let split = YAMLSource.splitKeyValue(afterDash) {
                let key = YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces))
                let value = YAMLSource.unquote(split.value.trimmingCharacters(in: .whitespaces))
                if key == "name" { name = value }
                if key == "type" { type = value }
            }

            var index = itemStart + 1
            while index < itemEnd {
                let line = source.line(index)
                if line.isIgnorable {
                    index += 1
                    continue
                }
                if line.startsSequenceItem {
                    index += 1
                    continue
                }
                guard line.indent > baseIndent,
                      let split = YAMLSource.splitKeyValue(line.content) else {
                    index += 1
                    continue
                }
                let key = YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces))
                switch key {
                case "name":
                    name = YAMLSource.unquote(split.value.trimmingCharacters(in: .whitespaces))
                case "type":
                    type = YAMLSource.unquote(split.value.trimmingCharacters(in: .whitespaces))
                case "proxies":
                    members = source.parseStringList(keyLineIndex: index, sectionRange: itemRange).map(\.value)
                case "use":
                    useProviders = source.parseStringList(keyLineIndex: index, sectionRange: itemRange).map(\.value)
                case "include-all", "include-all-proxies", "include-all-providers":
                    includeAll = YAMLSource.boolean(split.value) ?? false
                default:
                    break
                }
                index += 1
            }

            if !name.isEmpty {
                groups[name] = GroupDefinition(
                    name: name,
                    type: type,
                    members: members,
                    includeAll: includeAll,
                    useProviders: useProviders
                )
            }
        }
        return groups
    }

    private static func parseRuleProviders(_ source: YAMLSource) -> [String: RuleProvider] {
        guard let range = source.section(named: "rule-providers"),
              let baseIndent = source.bodyIndent(in: range) else {
            return [:]
        }
        let keyIndices = range.filter {
            let line = source.line($0)
            return !line.isIgnorable
                && line.indent == baseIndent
                && !line.startsSequenceItem
                && YAMLSource.splitKeyValue(line.content) != nil
        }

        var providers: [String: RuleProvider] = [:]
        for (position, keyIndex) in keyIndices.enumerated() {
            let end = position + 1 < keyIndices.count ? keyIndices[position + 1] : range.upperBound
            let keyLine = source.line(keyIndex)
            guard let split = YAMLSource.splitKeyValue(keyLine.content) else { continue }
            let name = YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces))
            var behavior = "classical"
            var payload: [String] = []
            var index = keyIndex + 1
            while index < end {
                let line = source.line(index)
                if line.isIgnorable {
                    index += 1
                    continue
                }
                guard !line.startsSequenceItem,
                      let property = YAMLSource.splitKeyValue(line.content) else {
                    index += 1
                    continue
                }
                let propertyKey = YAMLSource.unquote(
                    property.key.trimmingCharacters(in: .whitespaces)
                )
                if propertyKey == "behavior" {
                    behavior = YAMLSource.unquote(
                        property.value.trimmingCharacters(in: .whitespaces)
                    ).lowercased()
                } else if propertyKey == "payload" {
                    payload = source.parseStringList(
                        keyLineIndex: index,
                        sectionRange: index..<end
                    ).map(\.value)
                }
                index += 1
            }
            providers[name] = RuleProvider(name: name, behavior: behavior, payload: payload)
        }
        return providers
    }

    private static func parseProxyNames(_ source: YAMLSource) -> Set<String> {
        guard let range = source.section(named: "proxies"),
              let baseIndent = source.bodyIndent(in: range) else {
            return []
        }
        let itemIndices = range.filter {
            let line = source.line($0)
            return !line.isIgnorable && line.indent == baseIndent && line.startsSequenceItem
        }
        var names: Set<String> = []
        for itemStart in itemIndices {
            let line = source.line(itemStart)
            let afterDash = String(line.content.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            if afterDash.hasPrefix("{") {
                let flow = parseFlowMapping(afterDash)
                if let name = flow["name"] {
                    names.insert(name)
                }
            } else if let split = YAMLSource.splitKeyValue(afterDash) {
                let key = YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces))
                if key == "name" {
                    let name = YAMLSource.unquote(split.value.trimmingCharacters(in: .whitespaces))
                    if !name.isEmpty {
                        names.insert(name)
                    }
                }
            }
        }
        return names
    }

    private static func parseRules(_ source: YAMLSource) -> [ParsedRule] {
        guard let range = source.section(named: "rules") else { return [] }
        let keyLineIndex = range.lowerBound - 1
        let entries = source.parseList(keyLineIndex: keyLineIndex, sectionRange: range)
        return entries.map(parseRuleEntry)
    }

    private static func parseRuleEntry(_ entry: DNSServerEntry) -> ParsedRule {
        let raw = entry.raw
        var items = raw.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let type = items.first?.uppercased() ?? ""
        var target = ""
        var payload = ""
        var parameters: [String] = []

        if items.count > 1 {
            if type == "MATCH" {
                target = items[1]
            } else if ["AND", "OR", "NOT", "SUB-RULE"].contains(type) {
                if items.count > 2 {
                    target = items.removeLast()
                }
                payload = items.dropFirst().joined(separator: ",")
            } else {
                payload = items[1]
                if items.count > 2 {
                    target = items[2]
                }
                if items.count > 3 {
                    parameters = Array(items.dropFirst(3))
                }
            }
        }
        return ParsedRule(
            raw: raw,
            line: entry.line,
            tokenStart: entry.tokenStart,
            tokenEnd: entry.tokenEnd,
            quote: entry.quote,
            type: type,
            payload: payload,
            target: target,
            parameters: parameters,
            noResolve: parameters.contains("no-resolve") || parameters.contains("src")
        )
    }

    private static func parseTun(_ source: YAMLSource) -> (enabled: Bool?, dnsHijack: Bool) {
        guard let range = source.section(named: "tun"),
              let bodyIndent = source.bodyIndent(in: range) else {
            return (nil, false)
        }
        var enabled: Bool?
        var hijack = false
        var index = range.lowerBound
        while index < range.upperBound {
            let line = source.line(index)
            if line.isIgnorable || line.indent != bodyIndent || line.startsSequenceItem {
                index += 1
                continue
            }
            guard let split = YAMLSource.splitKeyValue(line.content) else {
                index += 1
                continue
            }
            let key = YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces))
            if key == "enable" {
                enabled = YAMLSource.boolean(split.value)
            } else if key == "dns-hijack" {
                let values = source.parseStringList(
                    keyLineIndex: index,
                    sectionRange: range
                ).map(\.value)
                hijack = values.contains { value in
                    value.replacingOccurrences(of: " ", with: "").hasSuffix(":53")
                }
            }
            index += 1
        }
        return (enabled, hijack)
    }

    static func splitPolicyKey(_ key: String) -> [String] {
        let lower = key.lowercased()
        for prefix in ["geosite:", "rule-set:"] where lower.hasPrefix(prefix) {
            let rest = String(key.dropFirst(prefix.count))
            return rest.split(separator: ",").map {
                prefix + $0.trimmingCharacters(in: .whitespaces)
            }
        }
        return key.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func keyRange(in line: YAMLLine, key: String) -> NSRange {
        let ns = line.raw as NSString
        let contentRange = NSRange(
            location: line.indent,
            length: max(0, ns.length - line.indent)
        )
        let found = ns.range(of: key, options: [], range: contentRange)
        guard found.location != NSNotFound else {
            return NSRange(location: line.indent, length: key.utf16.count)
        }
        return found
    }

    private static func parseFlowMapping(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "{}\t "))
        var quote: Character?
        var start = trimmed.startIndex
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character == "'" || character == "\"" {
                if quote == nil {
                    quote = character
                } else if quote == character {
                    quote = nil
                }
            } else if character == "," && quote == nil {
                parseFlowPair(String(trimmed[start..<index]), into: &result)
                start = trimmed.index(after: index)
            }
            index = trimmed.index(after: index)
        }
        parseFlowPair(String(trimmed[start...]), into: &result)
        return result
    }

    private static func parseFlowPair(_ raw: String, into result: inout [String: String]) {
        guard let colon = raw.firstIndex(of: ":") else { return }
        let key = raw[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        result[YAMLSource.unquote(key)] = YAMLSource.unquote(value)
    }

    private static func parseFlowArray(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]\t "))
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: ",").map {
            YAMLSource.unquote($0.trimmingCharacters(in: .whitespaces))
        }
    }
}
