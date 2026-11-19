import Darwin
import Foundation

public enum ConfigScanner {
    public static func analyze(text: String) throws -> ConfigAnalysis {
        let parsed = try ConfigParser.parse(text: text)
        let classifier = PolicyClassifier(parsed: parsed)
        var findings: [Finding] = []

        if let dns = parsed.dns {
            findings.append(contentsOf: dnsFindings(parsed: parsed, dns: dns, classifier: classifier))
        } else {
            findings.append(
                Finding(
                    id: "DNS-01-missing",
                    code: "DNS-01",
                    title: "mihomo DNS 未启用",
                    detail: "配置中没有 dns 段。IP 规则触发解析时，mihomo 会退回系统 DNS。",
                    recommendation: "开启 dns.enable，并把远程解析器设为加密 DoH/DoT 或绑定代理。",
                    severity: .low,
                    category: .possibleLeak,
                    locations: [SourceLocation(line: 1, label: "配置", snippet: "未找到 dns:") ],
                    fix: .enableMihomoDNS
                )
            )
        }

        let triggers = ruleTriggers(parsed: parsed, classifier: classifier)
        findings.append(contentsOf: ruleFindings(parsed: parsed, triggers: triggers, classifier: classifier))

        if parsed.tunEnabled == true, !parsed.tunDNSHijack {
            findings.append(
                Finding(
                    id: "TUN-01",
                    code: "TUN-01",
                    title: "TUN 未劫持 DNS",
                    detail: "tun.enable 为 true，但 dns-hijack 未包含 any:53。部分应用可能绕过 mihomo DNS。",
                    recommendation: "在 tun.dns-hijack 中加入 any:53，或确认系统 DNS 已指向 mihomo。",
                    severity: .medium,
                    category: .hardening
                )
            )
        }

        findings = deduplicate(findings)
        findings.sort {
            if $0.severity != $1.severity {
                return $0.severity > $1.severity
            }
            let lhsLine = $0.locations.first?.line ?? 0
            let rhsLine = $1.locations.first?.line ?? 0
            if lhsLine != rhsLine {
                return lhsLine < rhsLine
            }
            return $0.code < $1.code
        }

        let proxyGroups = proxyGroupOptions(parsed: parsed, classifier: classifier)
        let suggested = suggestedProxyGroup(from: proxyGroups)
        let score = protectionScore(findings: findings)
        var allServers: [DNSServerEntry] = []
        if let dns = parsed.dns {
            allServers.append(contentsOf: dns.nameserver)
            allServers.append(contentsOf: dns.fallback)
            allServers.append(contentsOf: dns.defaultNameserver)
            allServers.append(contentsOf: dns.proxyServerNameserver)
            allServers.append(contentsOf: dns.directNameserver)
            for policy in dns.policy {
                allServers.append(contentsOf: policy.servers)
            }
        }

        return ConfigAnalysis(
            findings: findings,
            proxyGroups: proxyGroups,
            suggestedProxyGroup: suggested,
            dnsEnabled: parsed.dns?.enable == true,
            totalLines: parsed.lines.count,
            score: score,
            dns: parsed.dns,
            ruleTriggers: triggers,
            allServerEntries: allServers
        )
    }

    private static func dnsFindings(
        parsed: ParsedConfig,
        dns: DNSBlock,
        classifier: PolicyClassifier
    ) -> [Finding] {
        var findings: [Finding] = []
        if dns.enable != true {
            let line = dns.enableLine.map { $0 + 1 } ?? (dns.startLine + 1)
            findings.append(
                Finding(
                    id: "DNS-01-\(dns.enableLine ?? dns.startLine)",
                    code: "DNS-01",
                    title: "mihomo DNS 未启用",
                    detail: dns.enable == false
                        ? "dns.enable 为 false，规则触发的解析会交给系统 DNS。"
                        : "dns 段没有明确设置 enable: true。",
                    recommendation: "将 dns.enable 设为 true；若缺失则生成最小加密 DNS 配置。",
                    severity: .low,
                    category: .possibleLeak,
                    locations: [SourceLocation(line: line, label: "DNS 开关", snippet: "enable: \(dns.enable.map(String.init) ?? "缺失")")],
                    fix: .enableMihomoDNS
                )
            )
        }

        let plainDefaults = (dns.nameserver + dns.fallback).filter {
            ServerParser.parse($0.raw).grade == .plain
        }
        if !plainDefaults.isEmpty {
            findings.append(
                Finding(
                    id: "DNS-02-\(plainDefaults[0].line)",
                    code: "DNS-02",
                    title: "nameserver / fallback 含明文 DNS",
                    detail: "检测到 \(plainDefaults.count) 个明文解析器：\(displayServers(plainDefaults))。mihomo 会向同一列表中的服务器并发查询。",
                    recommendation: "删除明文条目；需要国内解析时使用 https://223.5.5.5/dns-query 等加密地址。",
                    severity: .high,
                    category: .confirmedLeak,
                    locations: locations(for: plainDefaults, label: "明文解析器"),
                    fix: .removePlaintextDNS,
                    fixableLines: plainDefaults.map(\.line)
                )
            )
        }

        let plainProxyServers = dns.proxyServerNameserver.filter {
            ServerParser.parse($0.raw).grade == .plain
        }
        if !plainProxyServers.isEmpty {
            findings.append(
                Finding(
                    id: "DNS-09-\(plainProxyServers[0].line)",
                    code: "DNS-09",
                    title: "代理节点域名使用明文 DNS",
                    detail: "proxy-server-nameserver 含明文解析器：\(displayServers(plainProxyServers))。",
                    recommendation: "改用加密地址，例如 https://223.5.5.5/dns-query。",
                    severity: .medium,
                    category: .confirmedLeak,
                    locations: locations(for: plainProxyServers, label: "代理解析器"),
                    fix: .removePlaintextDNS,
                    fixableLines: plainProxyServers.map(\.line)
                )
            )
        }

        let unboundRemote = (dns.nameserver + dns.fallback).filter {
            let server = ServerParser.parse($0.raw)
            return (server.grade == .encryptedForeign || server.grade == .encryptedCN)
                && server.proxyName == nil
        }
        if dns.respectRules != true, !unboundRemote.isEmpty {
            findings.append(
                Finding(
                    id: "DNS-10-\(unboundRemote[0].line)",
                    code: "DNS-10",
                    title: "上游 DNS 未绑定代理",
                    detail: "\(unboundRemote.count) 个默认加密解析器会直接从本机网络发起查询；它们看不到明文内容，但仍能看到您的出口 IP 与访问域名。",
                    recommendation: "为这些地址追加 #代理组，或为国内域名单独配置 nameserver-policy。",
                    severity: .low,
                    category: .hardening,
                    locations: locations(for: unboundRemote, label: "未绑定解析器"),
                    fix: .bindDNSToProxy,
                    fixableLines: unboundRemote.map(\.line)
                )
            )
        }

        if !dns.fallback.isEmpty {
            findings.append(
                Finding(
                    id: "DNS-05-\(dns.mapEntries.first(where: { $0.key == "fallback" })?.line ?? dns.startLine)",
                    code: "DNS-05",
                    title: "fallback 会扩大并发解析范围",
                    detail: "未命中 fallback-filter 时，fallback 与 nameserver 可能同时收到查询。",
                    recommendation: "优先使用 nameserver-policy 按域名集分流；fallback 不是修复泄露的必要条件。",
                    severity: .info,
                    category: .redundantResolution
                )
            )
        }

        if dns.respectRules == true, dns.proxyServerNameserver.isEmpty {
            let line = dns.mapEntries.first(where: { $0.key == "respect-rules" })?.line ?? dns.startLine
            findings.append(
                Finding(
                    id: "DNS-06-\(line)",
                    code: "DNS-06",
                    title: "respect-rules 缺少代理解析器",
                    detail: "dns.respect-rules 为 true，但没有 proxy-server-nameserver，mihomo 可能加载失败。",
                    recommendation: "添加 proxy-server-nameserver，或关闭 respect-rules。",
                    severity: .critical,
                    category: .configError
                )
            )
        }

        for (offset, server) in dns.defaultNameserver.enumerated() {
            let parsedServer = ServerParser.parse(server.raw)
            if !parsedServer.isAcceptableDefaultNameserver {
                findings.append(
                    Finding(
                        id: "DNS-08-\(server.line)-\(offset)",
                        code: "DNS-08",
                        title: "default-nameserver 不是纯 IP",
                        detail: "\(server.raw) 不符合 mihomo 对启动解析器的要求。",
                        recommendation: "改成 IP、tls://IP 或 system；default-nameserver 不能依赖域名解析。",
                        severity: .critical,
                        category: .configError,
                        locations: [SourceLocation(line: server.line + 1, label: "启动解析器", snippet: server.raw)]
                    )
                )
            }
        }

        for entry in dns.mapEntries where !ConfigParser.dnsKeys.contains(entry.key) {
            let suggestion = closestKey(entry.key, candidates: ConfigParser.dnsKeys)
            if let suggestion, !dns.mapEntries.contains(where: { $0.key == suggestion }) {
                findings.append(
                    Finding(
                        id: "CFG-01-\(entry.line)",
                        code: "CFG-01",
                        title: "DNS 键名疑似拼写错误",
                        detail: "dns.\(entry.key) 不是已知键，mihomo 会静默忽略；它可能是 \(suggestion) 的笔误。",
                        recommendation: "确认后把键名改为 \(suggestion)。",
                        severity: .medium,
                        category: .configError,
                        locations: [SourceLocation(line: entry.line + 1, label: "DNS 键", snippet: entry.key)],
                        fix: .fixDNSKeyTypos,
                        fixableLines: [entry.line]
                    )
                )
            }
        }

        let allDefaultServers = dns.nameserver + dns.fallback
        for (offset, server) in allDefaultServers.enumerated() {
            let parsedServer = ServerParser.parse(server.raw)
            guard let proxyName = parsedServer.proxyName,
                  proxyName != "RULES",
                  !classifier.exists(proxyName) else {
                continue
            }
            findings.append(
                Finding(
                    id: "DNS-07-\(server.line)-\(offset)",
                    code: "DNS-07",
                    title: "DNS 绑定了不存在的策略",
                    detail: "\(server.raw) 的 #\(proxyName) 没有对应的代理或策略组，查询会失败。",
                    recommendation: "修正 # 后面的策略名，或在 proxy-groups / proxies 中补上定义。",
                    severity: .critical,
                    category: .configError,
                    locations: [SourceLocation(line: server.line + 1, label: "解析器", snippet: server.raw)]
                )
            )
        }

        let resolverLevel = ResolverLevel.worst(allDefaultServers, respectRules: dns.respectRules == true)
        for policy in dns.policy {
            let grade = ResolverLevel.worst(policy.servers, respectRules: false)
            guard grade == .plain || grade == .encryptedCN else { continue }
            let relation = policyRelation(
                key: policy.key,
                rules: parsed.rules,
                classifier: classifier
            )
            guard relation.isProxy else { continue }
            let severity: RiskLevel = grade == .plain ? .high : .medium
            findings.append(
                Finding(
                    id: "DNS-04-\(policy.line)-\(policy.key)",
                    code: "DNS-04",
                    title: "代理域名被本地 DNS 解析",
                    detail: "nameserver-policy 将代理类域名集 \(policy.key) 交给\(grade.label)，这些域名会被解析器看到。",
                    recommendation: "把该策略指向经代理的加密 DNS，例如 https://1.1.1.1/dns-query#代理组。",
                    severity: severity,
                    category: relation.confidence == .certain ? .confirmedLeak : .possibleLeak,
                    locations: [SourceLocation(line: policy.line + 1, label: "nameserver-policy", snippet: policy.key)]
                )
            )
        }

        // Rule findings use the same resolver level. Keeping it here makes the
        // relationship between local resolution and the configured resolver explicit.
        _ = resolverLevel
        return findings
    }

    private static func ruleTriggers(
        parsed: ParsedConfig,
        classifier: PolicyClassifier
    ) -> [RuleTrigger] {
        var triggers: [RuleTrigger] = []
        for (index, rule) in parsed.rules.enumerated() {
            guard rule.type != "MATCH", !rule.noResolve else { continue }
            let fixable: Bool
            switch rule.type {
            case "GEOIP", "IP-ASN", "IP-CIDR", "IP-CIDR6", "IP-SUFFIX":
                fixable = true
            case "RULE-SET":
                guard let provider = parsed.providers[rule.payload] else { continue }
                switch provider.behavior {
                case "ipcidr":
                    fixable = true
                case "classical":
                    fixable = provider.payload.contains { entry in
                        let parsedEntry = parseSimpleRule(entry)
                        return ["GEOIP", "IP-ASN", "IP-CIDR", "IP-CIDR6", "IP-SUFFIX"].contains(parsedEntry.type)
                            && !parsedEntry.parameters.contains("no-resolve")
                    }
                default:
                    continue
                }
            case "AND", "OR", "NOT":
                let containsResolving = ["GEOIP", "IP-ASN", "IP-CIDR", "IP-CIDR6", "IP-SUFFIX"].contains {
                    rule.payload.contains($0 + ",")
                }
                guard containsResolving else { continue }
                fixable = false
            default:
                continue
            }

            var downstream: [ParsedRule] = []
            var proxyMatch = false
            if index + 1 < parsed.rules.count {
                for next in parsed.rules[(index + 1)...] {
                    if next.type == "MATCH" {
                        proxyMatch = classifier.isProxyTarget(next.target)
                        break
                    }
                    if next.isDomainRule, classifier.isProxyTarget(next.target) {
                        downstream.append(next)
                    }
                    if next.type == "SUB-RULE" {
                        continue
                    }
                }
            }
            guard !downstream.isEmpty || proxyMatch else {
                continue
            }
            triggers.append(
                RuleTrigger(
                    rule: rule,
                    downstreamProxyRules: downstream,
                    hasProxyMatch: proxyMatch,
                    fixable: fixable
                )
            )
        }
        return triggers
    }

    private static func ruleFindings(
        parsed: ParsedConfig,
        triggers: [RuleTrigger],
        classifier: PolicyClassifier
    ) -> [Finding] {
        guard let dns = parsed.dns else {
            return triggers.map { trigger in
                Finding(
                    id: "RULE-01-\(trigger.rule.line)",
                    code: trigger.rule.type == "RULE-SET" ? "RULE-03" : "RULE-01",
                    title: "IP 规则会触发系统 DNS 解析",
                    detail: "\(trigger.rule.raw) 之前没有 no-resolve，且其后存在代理目标；DNS 未启用时解析交给系统。",
                    recommendation: "启用加密 DNS，并评估是否给该规则添加 no-resolve。",
                    severity: .high,
                    category: .confirmedLeak,
                    locations: [SourceLocation(line: trigger.rule.line + 1, label: "触发规则", snippet: trigger.rule.raw)],
                    fix: trigger.fixable ? .addNoResolve : nil,
                    fixableLines: trigger.fixable ? [trigger.rule.line] : []
                )
            }
        }

        let servers = dns.nameserver + dns.fallback
        let level = ResolverLevel.worst(servers, respectRules: dns.respectRules == true)
        var findings: [Finding] = []
        for trigger in triggers {
            let severity: RiskLevel
            let category: FindingCategory
            switch level {
            case .plain:
                severity = trigger.downstreamProxyRules.isEmpty ? .medium : .high
                category = trigger.downstreamProxyRules.isEmpty ? .possibleLeak : .confirmedLeak
            case .encryptedCN:
                severity = trigger.downstreamProxyRules.isEmpty ? .low : .medium
                category = .possibleLeak
            case .encryptedForeign:
                severity = .low
                category = .possibleLeak
            case .viaProxy:
                severity = .info
                category = .redundantResolution
            case .system:
                severity = .high
                category = .confirmedLeak
            }

            let proxyRuleText = trigger.downstreamProxyRules.isEmpty
                ? "MATCH 兜底的代理域名"
                : "\(trigger.downstreamProxyRules.count) 条后续代理域名规则"
            let detail: String
            if level == .viaProxy {
                detail = "\(trigger.rule.raw) 会使域名先在本地进入 mihomo DNS，再由代理发出；这不是直接泄露，但属于多余解析。"
            } else {
                detail = "\(trigger.rule.raw) 没有 no-resolve。走到该规则的\(proxyRuleText)会先由\(level.label)解析，然后才走代理。"
            }
            let code: String
            if trigger.rule.type == "RULE-SET" {
                code = "RULE-03"
            } else if ["AND", "OR", "NOT"].contains(trigger.rule.type) {
                code = "RULE-04"
            } else {
                code = trigger.hasProxyMatch && trigger.downstreamProxyRules.isEmpty ? "RULE-02" : "RULE-01"
            }
            findings.append(
                Finding(
                    id: "\(code)-\(trigger.rule.line)",
                    code: code,
                    title: level == .viaProxy ? "存在多余本地解析" : "IP 规则会触发本地 DNS",
                    detail: detail,
                    recommendation: trigger.fixable
                        ? "为该规则添加 no-resolve；若需要 GEOIP 对域名请求分流，请保留并把 DNS 绑定到代理。"
                        : "逻辑规则需要给内部 IP 子规则添加 no-resolve，建议手工调整。",
                    severity: severity,
                    category: category,
                    locations: [SourceLocation(line: trigger.rule.line + 1, label: "触发规则", snippet: trigger.rule.raw)],
                    fix: trigger.fixable ? .addNoResolve : nil,
                    fixableLines: trigger.fixable ? [trigger.rule.line] : []
                )
            )
        }
        _ = classifier
        return findings
    }

    private static func proxyGroupOptions(
        parsed: ParsedConfig,
        classifier: PolicyClassifier
    ) -> [ProxyGroupOption] {
        parsed.groups.values.compactMap { group in
            let result = classifier.classifyGroup(group.name)
            guard result.exists else { return nil }
            let classification: String
            switch result.policyClass {
            case .proxy:
                classification = result.assumed ? "mixedProxy" : "proxy"
            case .direct:
                classification = "direct"
            case .reject:
                classification = "reject"
            case .pass, .unknown:
                return nil
            }
            guard classification == "proxy" || classification == "mixedProxy" else {
                return nil
            }
            return ProxyGroupOption(
                name: group.name,
                type: group.type,
                classification: classification
            )
        }
        .sorted { lhs, rhs in
            let lhsRank = groupRank(lhs.name, type: lhs.type)
            let rhsRank = groupRank(rhs.name, type: rhs.type)
            if lhsRank != rhsRank {
                return lhsRank > rhsRank
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func suggestedProxyGroup(from groups: [ProxyGroupOption]) -> String? {
        groups.first?.name
    }

    private static func groupRank(_ name: String, type: String) -> Int {
        let lower = name.lowercased()
        var rank = type.lowercased() == "select" ? 20 : 0
        for token in ["手动", "选择", "proxy", "🚀", "🔰", "节点"] where lower.contains(token.lowercased()) {
            rank += 40
        }
        for token in ["直连", "direct", "漏网", "block", "reject", "广告", "ad"] where lower.contains(token.lowercased()) {
            rank -= 80
        }
        return rank
    }

    private static func protectionScore(findings: [Finding]) -> Int {
        var score = 100
        for finding in findings {
            switch finding.severity {
            case .critical: score -= 25
            case .high: score -= 16
            case .medium: score -= 8
            case .low: score -= 3
            case .info: break
            }
        }
        return max(0, min(100, score))
    }

    private static func deduplicate(_ findings: [Finding]) -> [Finding] {
        var seen: Set<String> = []
        return findings.filter { finding in
            seen.insert(finding.id).inserted
        }
    }

    private static func locations(for servers: [DNSServerEntry], label: String) -> [SourceLocation] {
        servers.prefix(8).map {
            SourceLocation(line: $0.line + 1, label: label, snippet: $0.raw)
        }
    }

    private static func displayServers(_ servers: [DNSServerEntry]) -> String {
        servers.prefix(5).map(\.raw).joined(separator: ", ")
    }

    private static func parseSimpleRule(_ raw: String) -> ParsedRule {
        let items = raw.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let type = items.first?.uppercased() ?? ""
        let payload = items.count > 1 ? items[1] : ""
        let target = items.count > 2 ? items[2] : ""
        let parameters = items.count > 3 ? Array(items.dropFirst(3)) : []
        return ParsedRule(
            raw: raw,
            line: 0,
            tokenStart: 0,
            tokenEnd: 0,
            quote: nil,
            type: type,
            payload: payload,
            target: target,
            parameters: parameters,
            noResolve: parameters.contains("no-resolve")
        )
    }

    private static func policyRelation(
        key: String,
        rules: [ParsedRule],
        classifier: PolicyClassifier
    ) -> PolicyRelation {
        let lower = key.lowercased()
        if lower.hasPrefix("geosite:") {
            let set = String(key.dropFirst("geosite:".count))
            if let rule = rules.first(where: {
                $0.type == "GEOSITE" && $0.payload.caseInsensitiveCompare(set) == .orderedSame
            }) {
                let proxy = classifier.isProxyTarget(rule.target)
                return PolicyRelation(isProxy: proxy, confidence: .certain)
            }
            let known: Set<String> = [
                "google", "youtube", "twitter", "telegram", "github", "openai",
                "netflix", "spotify", "geolocation-!cn", "category-scholar-!cn"
            ]
            return PolicyRelation(isProxy: known.contains(set.lowercased()), confidence: .possible)
        }
        if lower.hasPrefix("rule-set:") {
            let set = String(key.dropFirst("rule-set:".count))
            if let rule = rules.first(where: {
                $0.type == "RULE-SET" && $0.payload == set
            }) {
                return PolicyRelation(
                    isProxy: classifier.isProxyTarget(rule.target),
                    confidence: .certain
                )
            }
            return PolicyRelation(isProxy: false, confidence: .possible)
        }

        for rule in rules where rule.type == "DOMAIN" || rule.type == "DOMAIN-SUFFIX" {
            let matches = rule.type == "DOMAIN"
                ? lower == rule.payload.lowercased()
                : lower == rule.payload.lowercased() || lower.hasSuffix("." + rule.payload.lowercased())
            if matches {
                return PolicyRelation(
                    isProxy: classifier.isProxyTarget(rule.target),
                    confidence: .certain
                )
            }
        }
        return PolicyRelation(isProxy: false, confidence: .possible)
    }

    static func closestKey(_ key: String, candidates: Set<String>) -> String? {
        let lower = key.lowercased()
        var best: String?
        var bestDistance = 3
        for candidate in candidates {
            let distance = editDistance(lower, candidate)
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        guard let best, bestDistance * 2 < lower.count else { return nil }
        return best
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var matrix = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )
        for index in 0...left.count { matrix[index][0] = index }
        for index in 0...right.count { matrix[0][index] = index }
        for i in 1...left.count {
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
                if i > 1, j > 1, left[i - 1] == right[j - 2], left[i - 2] == right[j - 1] {
                    matrix[i][j] = min(matrix[i][j], matrix[i - 2][j - 2] + 1)
                }
            }
        }
        return matrix[left.count][right.count]
    }
}

enum ServerGrade {
    case plain
    case encryptedCN
    case encryptedForeign
    case viaProxy
    case safe
    case invalid
}

enum ResolverLevel: Int, Comparable {
    case viaProxy = 0
    case encryptedForeign = 1
    case encryptedCN = 2
    case plain = 3
    case system = 4

    static func < (lhs: ResolverLevel, rhs: ResolverLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .plain: "明文 DNS"
        case .encryptedCN: "国内加密 DNS"
        case .encryptedForeign: "国外加密 DNS"
        case .viaProxy: "经代理的安全 DNS"
        case .system: "系统 DNS"
        }
    }

    static func worst(_ servers: [DNSServerEntry], respectRules: Bool) -> ResolverLevel {
        if servers.isEmpty {
            return .encryptedCN
        }
        var worst: ResolverLevel = .viaProxy
        for server in servers {
            let parsed = ServerParser.parse(server.raw)
            let level: ResolverLevel
            switch parsed.grade {
            case .plain, .invalid:
                level = .plain
            case .encryptedCN:
                level = .encryptedCN
            case .encryptedForeign:
                level = respectRules && parsed.proxyName == nil ? .viaProxy : .encryptedForeign
            case .viaProxy:
                level = .viaProxy
            case .safe:
                level = .viaProxy
            }
            if level > worst {
                worst = level
            }
        }
        return worst
    }
}

struct ParsedDNSServer {
    let raw: String
    let scheme: String
    let host: String
    let proxyName: String?
    let grade: ServerGrade

    var isAcceptableDefaultNameserver: Bool {
        if scheme == "system" { return true }
        if grade == .invalid { return false }
        return ServerParser.isIPLiteral(host)
    }
}

enum ServerParser {
    static func parse(_ raw: String) -> ParsedDNSServer {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fragmentParts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let base = String(fragmentParts[0])
        let fragment = fragmentParts.count > 1 ? String(fragmentParts[1]) : ""
        var proxyName: String?
        if !fragment.isEmpty {
            for part in fragment.split(separator: "&") {
                let text = String(part)
                if !text.contains("=") {
                    proxyName = text.removingPercentEncoding ?? text
                    break
                }
            }
        }

        if trimmed == "system" || trimmed.hasPrefix("system://") {
            return ParsedDNSServer(raw: raw, scheme: "system", host: "", proxyName: nil, grade: .plain)
        }
        if trimmed.hasPrefix("rcode://") {
            return ParsedDNSServer(raw: raw, scheme: "rcode", host: "", proxyName: nil, grade: .safe)
        }
        if trimmed.hasPrefix("dhcp://") {
            return ParsedDNSServer(raw: raw, scheme: "dhcp", host: "", proxyName: nil, grade: .plain)
        }
        for scheme in ["ts", "tailscale", "et", "easytier"] where trimmed.hasPrefix(scheme + "://") {
            return ParsedDNSServer(raw: raw, scheme: scheme, host: "", proxyName: nil, grade: .viaProxy)
        }

        var scheme = "udp"
        var hostPart = base
        if let separator = base.range(of: "://") {
            scheme = String(base[..<separator.lowerBound]).lowercased()
            hostPart = String(base[separator.upperBound...])
        }
        if hostPart.hasPrefix("[") {
            if let closing = hostPart.firstIndex(of: "]") {
                hostPart = String(hostPart[hostPart.index(after: hostPart.startIndex)..<closing])
            }
        } else {
            hostPart = String(
                hostPart.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0]
            )
            hostPart = String(
                hostPart.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
            )
            if hostPart.filter({ $0 == ":" }).count == 1 {
                hostPart = String(hostPart.split(separator: ":", maxSplits: 1)[0])
            }
        }
        let host = hostPart.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()

        let grade: ServerGrade
        switch scheme {
        case "udp", "tcp", "http":
            grade = .plain
        case "tls", "https", "quic", "h3":
            if proxyName != nil {
                grade = .viaProxy
            } else if isCNResolver(host) {
                grade = .encryptedCN
            } else {
                grade = .encryptedForeign
            }
        default:
            grade = .invalid
        }
        return ParsedDNSServer(
            raw: raw,
            scheme: scheme,
            host: host,
            proxyName: proxyName,
            grade: grade
        )
    }

    static func isIPLiteral(_ host: String) -> Bool {
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return true
        }
        var ipv6 = in6_addr()
        return host.withCString { inet_pton(AF_INET6, $0, &ipv6) } == 1
    }

    private static func isCNResolver(_ host: String) -> Bool {
        if host.hasSuffix(".cn") || host.hasSuffix(".qq.com") {
            return true
        }
        let knownHosts: Set<String> = [
            "doh.pub", "dot.pub", "dns.alidns.com", "doh.360.cn",
            "dns.pub", "doh.volces.com"
        ]
        if knownHosts.contains(host) {
            return true
        }
        let knownIPs: Set<String> = [
            "223.5.5.5", "223.6.6.6", "1.12.12.12", "120.53.53.53",
            "119.29.29.29", "180.76.76.76", "114.114.114.114",
            "2400:3200::1", "2400:3200:baba::1"
        ]
        return knownIPs.contains(host)
    }
}

enum PolicyClass {
    case proxy
    case direct
    case reject
    case pass
    case unknown
}

struct PolicyResult {
    let policyClass: PolicyClass
    let exists: Bool
    let assumed: Bool
}

final class PolicyClassifier {
    private let parsed: ParsedConfig
    private var cache: [String: PolicyResult] = [:]

    init(parsed: ParsedConfig) {
        self.parsed = parsed
    }

    func classifyGroup(_ name: String) -> PolicyResult {
        classify(name, visiting: [])
    }

    func isProxyTarget(_ name: String) -> Bool {
        classify(name, visiting: []).policyClass == .proxy
    }

    func exists(_ name: String) -> Bool {
        classify(name, visiting: []).exists
    }

    private func classify(_ name: String, visiting: Set<String>) -> PolicyResult {
        if let cached = cache[name] {
            return cached
        }
        switch name.uppercased() {
        case "DIRECT", "COMPATIBLE":
            let result = PolicyResult(policyClass: .direct, exists: true, assumed: false)
            cache[name] = result
            return result
        case "REJECT", "REJECT-DROP":
            let result = PolicyResult(policyClass: .reject, exists: true, assumed: false)
            cache[name] = result
            return result
        case "PASS":
            let result = PolicyResult(policyClass: .pass, exists: true, assumed: false)
            cache[name] = result
            return result
        case "GLOBAL":
            let result = PolicyResult(policyClass: .proxy, exists: true, assumed: false)
            cache[name] = result
            return result
        default:
            break
        }

        if parsed.proxyNames.contains(name) {
            let result = PolicyResult(policyClass: .proxy, exists: true, assumed: false)
            cache[name] = result
            return result
        }

        guard let group = parsed.groups[name] else {
            // Group members are usually node names. Unreferenced names are
            // assumed to be proxies so rule routing is not underestimated.
            let result = PolicyResult(policyClass: .proxy, exists: false, assumed: false)
            cache[name] = result
            return result
        }
        guard !visiting.contains(name) else {
            let result = PolicyResult(policyClass: .proxy, exists: true, assumed: true)
            cache[name] = result
            return result
        }
        var nextVisiting = visiting
        nextVisiting.insert(name)

        var hasProxy = group.includeAll || !group.useProviders.isEmpty
        var hasOther = false
        var assumed = false
        for member in group.members {
            let result = classify(member, visiting: nextVisiting)
            switch result.policyClass {
            case .proxy:
                hasProxy = true
                assumed = assumed || result.assumed || !result.exists
            case .direct, .reject, .pass:
                hasOther = true
            case .unknown:
                break
            }
        }

        let result: PolicyResult
        if hasProxy {
            result = PolicyResult(policyClass: .proxy, exists: true, assumed: assumed || hasOther)
        } else if group.members.contains(where: { $0.uppercased() == "DIRECT" }) {
            result = PolicyResult(policyClass: .direct, exists: true, assumed: false)
        } else if group.members.contains(where: { $0.uppercased().hasPrefix("REJECT") }) {
            result = PolicyResult(policyClass: .reject, exists: true, assumed: false)
        } else {
            result = PolicyResult(policyClass: .direct, exists: true, assumed: false)
        }
        cache[name] = result
        return result
    }
}

private struct PolicyRelation {
    enum Confidence {
        case certain
        case possible
    }

    let isProxy: Bool
    let confidence: Confidence
}
