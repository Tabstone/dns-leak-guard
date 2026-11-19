import Foundation

public enum RiskLevel: Int, CaseIterable, Comparable, Sendable {
    case info = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .info: "提示"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        case .critical: "严重"
        }
    }
}

public enum FindingCategory: String, Sendable {
    case confirmedLeak
    case possibleLeak
    case configError
    case redundantResolution
    case hardening

    public var label: String {
        switch self {
        case .confirmedLeak: "已确认风险"
        case .possibleLeak: "可能泄露"
        case .configError: "配置错误"
        case .redundantResolution: "多余解析"
        case .hardening: "加固建议"
        }
    }
}

public struct SourceLocation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let line: Int
    public let label: String
    public let snippet: String

    public init(line: Int, label: String, snippet: String) {
        self.id = UUID()
        self.line = line
        self.label = label
        self.snippet = snippet
    }
}

public struct Finding: Identifiable, Hashable, Sendable {
    public let id: String
    public let code: String
    public let title: String
    public let detail: String
    public let recommendation: String
    public let severity: RiskLevel
    public let category: FindingCategory
    public let locations: [SourceLocation]
    public let fix: FixOptionType?
    public let fixableLines: [Int]

    public init(
        id: String = UUID().uuidString,
        code: String,
        title: String,
        detail: String,
        recommendation: String,
        severity: RiskLevel,
        category: FindingCategory,
        locations: [SourceLocation] = [],
        fix: FixOptionType? = nil,
        fixableLines: [Int] = []
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.detail = detail
        self.recommendation = recommendation
        self.severity = severity
        self.category = category
        self.locations = locations
        self.fix = fix
        self.fixableLines = fixableLines
    }
}

public enum FixOptionType: String, CaseIterable, Identifiable, Sendable {
    case removePlaintextDNS
    case bindDNSToProxy
    case enableMihomoDNS
    case fixDNSKeyTypos
    case addNoResolve

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .removePlaintextDNS: "移除明文 DNS"
        case .bindDNSToProxy: "将上游 DNS 绑定到代理"
        case .enableMihomoDNS: "启用 mihomo DNS"
        case .fixDNSKeyTypos: "修正 DNS 键名拼写"
        case .addNoResolve: "为 IP 规则添加 no-resolve"
        }
    }

    public var detail: String {
        switch self {
        case .removePlaintextDNS:
            "删除 UDP、TCP、HTTP、system 等明文解析器；若列表会变空，则保留一个加密 DoH。"
        case .bindDNSToProxy:
            "给 nameserver / fallback 的远程加密 DNS 追加 #代理组，使 DNS 查询经代理发出。"
        case .enableMihomoDNS:
            "确保 dns.enable 为 true；缺失时生成最小加密 DNS 配置。"
        case .fixDNSKeyTypos:
            "修正 dns 段中会被 mihomo 静默忽略的近似拼写错误，比如 nameserver-police。"
        case .addNoResolve:
            "阻止 IP 规则触发的本地解析。可能改变 GEOIP 对域名请求的分流结果，默认关闭。"
        }
    }

    public var isAdvanced: Bool {
        self == .addNoResolve
    }
}

public struct FixSelection: Sendable {
    public var removePlaintextDNS: Bool
    public var bindDNSToProxy: Bool
    public var enableMihomoDNS: Bool
    public var fixDNSKeyTypos: Bool
    public var addNoResolve: Bool

    public init(
        removePlaintextDNS: Bool = true,
        bindDNSToProxy: Bool = true,
        enableMihomoDNS: Bool = true,
        fixDNSKeyTypos: Bool = true,
        addNoResolve: Bool = false
    ) {
        self.removePlaintextDNS = removePlaintextDNS
        self.bindDNSToProxy = bindDNSToProxy
        self.enableMihomoDNS = enableMihomoDNS
        self.fixDNSKeyTypos = fixDNSKeyTypos
        self.addNoResolve = addNoResolve
    }

    public func isEnabled(_ type: FixOptionType) -> Bool {
        switch type {
        case .removePlaintextDNS: removePlaintextDNS
        case .bindDNSToProxy: bindDNSToProxy
        case .enableMihomoDNS: enableMihomoDNS
        case .fixDNSKeyTypos: fixDNSKeyTypos
        case .addNoResolve: addNoResolve
        }
    }

    public func set(_ type: FixOptionType, enabled: Bool) -> FixSelection {
        var copy = self
        switch type {
        case .removePlaintextDNS: copy.removePlaintextDNS = enabled
        case .bindDNSToProxy: copy.bindDNSToProxy = enabled
        case .enableMihomoDNS: copy.enableMihomoDNS = enabled
        case .fixDNSKeyTypos: copy.fixDNSKeyTypos = enabled
        case .addNoResolve: copy.addNoResolve = enabled
        }
        return copy
    }
}

public struct ProxyGroupOption: Identifiable, Hashable, Sendable {
    public let name: String
    public let type: String
    public let classification: String

    public var id: String { name }

    public init(name: String, type: String, classification: String) {
        self.name = name
        self.type = type
        self.classification = classification
    }
}

public struct ConfigAnalysis: Sendable {
    public let findings: [Finding]
    public let proxyGroups: [ProxyGroupOption]
    public let suggestedProxyGroup: String?
    public let dnsEnabled: Bool
    public let totalLines: Int
    public let score: Int

    internal let dns: DNSBlock?
    internal let ruleTriggers: [RuleTrigger]
    internal let allServerEntries: [DNSServerEntry]

    public var highestRisk: RiskLevel {
        findings.map(\.severity).max() ?? .info
    }

    public var actionableFindingCount: Int {
        findings.filter { $0.fix != nil }.count
    }

    public func findingCount(for option: FixOptionType) -> Int {
        findings.filter { $0.fix == option }.count
    }
}

public struct DNSObservation: Identifiable, Hashable, Sendable {
    public let id: String
    public let ip: String
    public let countryCode: String
    public let location: String
    public let isp: String

    public init(ip: String, countryCode: String, location: String, isp: String) {
        self.id = ip
        self.ip = ip
        self.countryCode = countryCode
        self.location = location
        self.isp = isp
    }
}

public struct LiveDNSTestResult: Sendable {
    public enum Outcome: Sendable {
        case singleResolverPath
        case multipleResolverPaths
        case error
    }

    public let observations: [DNSObservation]
    public let queriesSucceeded: Int
    public let queriesAttempted: Int
    public let outcome: Outcome
    public let message: String
    public let testedAt: Date

    public init(
        observations: [DNSObservation],
        queriesSucceeded: Int,
        queriesAttempted: Int,
        outcome: Outcome,
        message: String,
        testedAt: Date = Date()
    ) {
        self.observations = observations
        self.queriesSucceeded = queriesSucceeded
        self.queriesAttempted = queriesAttempted
        self.outcome = outcome
        self.message = message
        self.testedAt = testedAt
    }

    public var uniqueISPs: [String] {
        Array(Set(observations.map(\.isp))).sorted()
    }

    public var uniqueLocations: [String] {
        Array(Set(observations.map(\.location))).sorted()
    }

    public var resolverCount: Int {
        Set(observations.map(\.ip)).count
    }
}

public struct WorkspaceInfo: Sendable {
    public let directory: URL
    public let activeConfig: URL
    public let dnsOverride: URL?
    public let vergeSettings: URL?
    public let profilesFile: URL?
    public let controlSocket: URL?
    public let isClashVergeRunning: Bool

    public init(
        directory: URL,
        activeConfig: URL,
        dnsOverride: URL?,
        vergeSettings: URL?,
        profilesFile: URL?,
        controlSocket: URL?,
        isClashVergeRunning: Bool
    ) {
        self.directory = directory
        self.activeConfig = activeConfig
        self.dnsOverride = dnsOverride
        self.vergeSettings = vergeSettings
        self.profilesFile = profilesFile
        self.controlSocket = controlSocket
        self.isClashVergeRunning = isClashVergeRunning
    }
}

public struct ClashRuntimeStatus: Sendable {
    public let mode: String?
    public let tunEnabled: Bool?
    public let mixedPort: Int?
    public let globalSelection: String?

    public init(
        mode: String?,
        tunEnabled: Bool?,
        mixedPort: Int?,
        globalSelection: String?
    ) {
        self.mode = mode
        self.tunEnabled = tunEnabled
        self.mixedPort = mixedPort
        self.globalSelection = globalSelection
    }
}

public struct WorkspaceHealth: Sendable {
    public let profileDNSOverrideEnabled: Bool?
    public let warnings: [String]

    public init(profileDNSOverrideEnabled: Bool?, warnings: [String]) {
        self.profileDNSOverrideEnabled = profileDNSOverrideEnabled
        self.warnings = warnings
    }
}

public struct FileBackup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let original: URL
    public let backup: URL

    public init(original: URL, backup: URL) {
        self.id = UUID()
        self.original = original
        self.backup = backup
    }
}

public struct FixApplicationReport: Sendable {
    public let changedFiles: [URL]
    public let backups: [FileBackup]
    public let changeCount: Int
    public let appliedActions: [FixOptionType]
    public let notes: [String]
    public let reloadSucceeded: Bool
    public let reloadMessage: String

    public init(
        changedFiles: [URL],
        backups: [FileBackup],
        changeCount: Int,
        appliedActions: [FixOptionType],
        notes: [String],
        reloadSucceeded: Bool,
        reloadMessage: String
    ) {
        self.changedFiles = changedFiles
        self.backups = backups
        self.changeCount = changeCount
        self.appliedActions = appliedActions
        self.notes = notes
        self.reloadSucceeded = reloadSucceeded
        self.reloadMessage = reloadMessage
    }
}

// Internal source-aware structures used by the scanner and fix engine.
struct DNSServerEntry: Sendable {
    let raw: String
    let list: DNSListKind?
    let line: Int
    let tokenStart: Int
    let tokenEnd: Int
    let quote: Character?
    let policyKey: String?
    let policySubkey: String?
}

enum DNSListKind: String, Sendable {
    case nameserver
    case fallback
    case defaultNameserver = "default-nameserver"
    case proxyServerNameserver = "proxy-server-nameserver"
    case directNameserver = "direct-nameserver"
    case policy = "nameserver-policy"
}

struct DNSMapEntry: Sendable {
    let key: String
    let line: Int
    let keyStart: Int
    let keyEnd: Int
    let value: String?
}

struct PolicyEntry: Sendable {
    let key: String
    let line: Int
    let servers: [DNSServerEntry]
}

struct DNSBlock: Sendable {
    let startLine: Int
    let endLine: Int
    let bodyIndent: Int
    let enableLine: Int?
    let enable: Bool?
    let mapEntries: [DNSMapEntry]
    let nameserver: [DNSServerEntry]
    let fallback: [DNSServerEntry]
    let defaultNameserver: [DNSServerEntry]
    let proxyServerNameserver: [DNSServerEntry]
    let directNameserver: [DNSServerEntry]
    let policy: [PolicyEntry]
    let ipv6: Bool?
    let respectRules: Bool?
}

struct RuleProvider: Sendable {
    let name: String
    let behavior: String
    let payload: [String]
}

struct ParsedRule: Sendable {
    let raw: String
    let line: Int
    let tokenStart: Int
    let tokenEnd: Int
    let quote: Character?
    let type: String
    let payload: String
    let target: String
    let parameters: [String]
    let noResolve: Bool

    var isSimpleResolvingRule: Bool {
        ["GEOIP", "IP-ASN", "IP-CIDR", "IP-CIDR6", "IP-SUFFIX"].contains(type)
    }

    var isDomainRule: Bool {
        ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX", "DOMAIN-WILDCARD", "GEOSITE"].contains(type)
    }
}

struct RuleTrigger: Sendable {
    let rule: ParsedRule
    let downstreamProxyRules: [ParsedRule]
    let hasProxyMatch: Bool
    let fixable: Bool
}

struct ParsedConfig: Sendable {
    let text: String
    let lineEnding: String
    let lines: [String]
    let dns: DNSBlock?
    let groups: [String: GroupDefinition]
    let proxyNames: Set<String>
    let rules: [ParsedRule]
    let providers: [String: RuleProvider]
    let tunEnabled: Bool?
    let tunDNSHijack: Bool
    let hasYAMLAnchors: Bool
}

struct GroupDefinition: Sendable {
    let name: String
    let type: String
    let members: [String]
    let includeAll: Bool
    let useProviders: [String]
}
