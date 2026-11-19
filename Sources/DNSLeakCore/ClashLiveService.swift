import Darwin
import Foundation

public enum ClashLiveError: LocalizedError {
    case invalidResponse(String)
    case http(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidResponse(message):
            "mihomo 控制器响应无法解析：\(message)"
        case let .http(message):
            "mihomo 控制器请求失败：\(message)"
        }
    }
}

public struct ClashLiveConnection: Identifiable, Sendable {
    public let id: String
    public let host: String
    public let destinationIP: String?
    public let destinationPort: String?
    public let network: String?
    public let inbound: String?
    public let ruleType: String
    public let rulePayload: String
    public let chains: [String]
    public let download: Int64
    public let upload: Int64
    public let start: String?
    public let processName: String?
    public let processPath: String?

    public init(
        id: String,
        host: String,
        destinationIP: String?,
        destinationPort: String?,
        network: String?,
        inbound: String?,
        ruleType: String,
        rulePayload: String,
        chains: [String],
        download: Int64,
        upload: Int64,
        start: String?,
        processName: String?,
        processPath: String?
    ) {
        self.id = id
        self.host = host
        self.destinationIP = destinationIP
        self.destinationPort = destinationPort
        self.network = network
        self.inbound = inbound
        self.ruleType = ruleType
        self.rulePayload = rulePayload
        self.chains = chains
        self.download = download
        self.upload = upload
        self.start = start
        self.processName = processName
        self.processPath = processPath
    }
}

public struct ClashLiveProxyGroup: Identifiable, Hashable, Sendable {
    public let name: String
    public let type: String
    public let selected: String?
    public let memberCount: Int
    public let delay: Int?
    public let members: [ClashLiveProxyMember]

    public var id: String { name }

    public var isUserSelectable: Bool {
        ["Selector", "Select", "Relay"].contains(type)
    }

    public init(
        name: String,
        type: String,
        selected: String?,
        memberCount: Int,
        delay: Int?,
        members: [ClashLiveProxyMember] = []
    ) {
        self.name = name
        self.type = type
        self.selected = selected
        self.memberCount = memberCount
        self.delay = delay
        self.members = members
    }
}

public struct ClashLiveProxyMember: Identifiable, Hashable, Sendable {
    public let name: String
    public let type: String
    public let delay: Int?

    public var id: String { name }

    public init(name: String, type: String, delay: Int?) {
        self.name = name
        self.type = type
        self.delay = delay
    }
}

public struct ClashProxySnapshot: Sendable {
    public let groups: [ClashLiveProxyGroup]
    public let targetNames: Set<String>

    public init(groups: [ClashLiveProxyGroup], targetNames: Set<String>) {
        self.groups = groups
        self.targetNames = targetNames
    }
}

public struct ClashLiveRule: Identifiable, Hashable, Sendable {
    public let id: String
    public let index: Int
    public let type: String
    public let payload: String
    public let target: String
    public let hitCount: Int
    public let missCount: Int
    public let disabled: Bool

    public init(
        id: String,
        index: Int,
        type: String,
        payload: String,
        target: String,
        hitCount: Int,
        missCount: Int,
        disabled: Bool
    ) {
        self.id = id
        self.index = index
        self.type = type
        self.payload = payload
        self.target = target
        self.hitCount = hitCount
        self.missCount = missCount
        self.disabled = disabled
    }
}

public struct ClashLiveRuleProvider: Identifiable, Hashable, Sendable {
    public let name: String
    public let behavior: String
    public let format: String
    public let vehicleType: String
    public let ruleCount: Int
    public let updatedAt: String?

    public var id: String { name }

    public init(
        name: String,
        behavior: String,
        format: String,
        vehicleType: String,
        ruleCount: Int,
        updatedAt: String?
    ) {
        self.name = name
        self.behavior = behavior
        self.format = format
        self.vehicleType = vehicleType
        self.ruleCount = ruleCount
        self.updatedAt = updatedAt
    }
}

public struct ClashLiveDomain: Identifiable, Sendable {
    public let id: String
    public let host: String
    public let isIP: Bool
    public let destinationIP: String?
    public let destinationPort: String?
    public let network: String?
    public let inbound: String?
    public let ruleType: String
    public let rulePayload: String
    public let chains: [String]
    public let exitName: String?
    public let nodeName: String?
    public let processNames: [String]
    public let download: Int64
    public let upload: Int64
    public let downloadRate: Double
    public let uploadRate: Double
    public let activeConnections: Int
    public let connectionCount: Int
    public let firstSeen: Date
    public let lastSeen: Date
    public let variants: [ClashLiveVariant]

    public init(
        id: String,
        host: String,
        isIP: Bool,
        destinationIP: String?,
        destinationPort: String?,
        network: String?,
        inbound: String?,
        ruleType: String,
        rulePayload: String,
        chains: [String],
        exitName: String?,
        nodeName: String?,
        processNames: [String],
        download: Int64,
        upload: Int64,
        downloadRate: Double,
        uploadRate: Double,
        activeConnections: Int,
        connectionCount: Int,
        firstSeen: Date,
        lastSeen: Date,
        variants: [ClashLiveVariant]
    ) {
        self.id = id
        self.host = host
        self.isIP = isIP
        self.destinationIP = destinationIP
        self.destinationPort = destinationPort
        self.network = network
        self.inbound = inbound
        self.ruleType = ruleType
        self.rulePayload = rulePayload
        self.chains = chains
        self.exitName = exitName
        self.nodeName = nodeName
        self.processNames = processNames
        self.download = download
        self.upload = upload
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.activeConnections = activeConnections
        self.connectionCount = connectionCount
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.variants = variants
    }
}

public struct ClashLiveVariant: Identifiable, Hashable, Sendable {
    public let ruleType: String
    public let rulePayload: String
    public let exitName: String?
    public let nodeName: String?
    public let count: Int

    public var id: String {
        "\(ruleType)|\(rulePayload)|\(exitName ?? "")|\(nodeName ?? "")"
    }

    public init(
        ruleType: String,
        rulePayload: String,
        exitName: String?,
        nodeName: String?,
        count: Int
    ) {
        self.ruleType = ruleType
        self.rulePayload = rulePayload
        self.exitName = exitName
        self.nodeName = nodeName
        self.count = count
    }
}

public struct ClashTrafficAccumulator: Sendable {
    private struct Ledger {
        let download: Int64
        let upload: Int64
    }

    private struct State {
        var host: String
        var isIP: Bool
        var destinationIP: String?
        var destinationPort: String?
        var network: String?
        var inbound: String?
        var ruleType: String
        var rulePayload: String
        var chains: [String]
        var processes: Set<String>
        var download: Int64
        var upload: Int64
        var downloadRate: Double
        var uploadRate: Double
        var active: Int
        var count: Int
        var firstSeen: Date
        var lastSeen: Date
        var variants: [String: ClashLiveVariant]
    }

    private var ledger: [String: Ledger] = [:]
    private var states: [String: State] = [:]
    private var lastSample: Date?

    public init() {}

    public mutating func ingest(
        _ connections: [ClashLiveConnection],
        now: Date = Date()
    ) -> [ClashLiveDomain] {
        let elapsed = max(
            0.25,
            now.timeIntervalSince(lastSample ?? now.addingTimeInterval(-1))
        )
        lastSample = now

        var nextLedger: [String: Ledger] = [:]
        var activeByKey: [String: Int] = [:]
        var rateDownByKey: [String: Double] = [:]
        var rateUpByKey: [String: Double] = [:]

        for connection in connections {
            let host = connection.host.isEmpty ? "未知目标" : connection.host
            let key = host.lowercased()
            let existingState = states[key] != nil
            let previous = ledger[connection.id]
            let downDelta = previous.map {
                max(0, connection.download - $0.download)
            } ?? connection.download
            let upDelta = previous.map {
                max(0, connection.upload - $0.upload)
            } ?? connection.upload
            nextLedger[connection.id] = Ledger(
                download: connection.download,
                upload: connection.upload
            )

            var state = states[key] ?? State(
                host: host,
                isIP: isIPAddress(host),
                destinationIP: connection.destinationIP,
                destinationPort: connection.destinationPort,
                network: connection.network,
                inbound: connection.inbound,
                ruleType: connection.ruleType,
                rulePayload: connection.rulePayload,
                chains: connection.chains,
                processes: [],
                download: 0,
                upload: 0,
                downloadRate: 0,
                uploadRate: 0,
                active: 0,
                count: 0,
                firstSeen: now,
                lastSeen: now,
                variants: [:]
            )
            if !existingState {
                state.count += 1
            }
            state.host = host
            state.isIP = isIPAddress(host)
            state.destinationIP = connection.destinationIP ?? state.destinationIP
            state.destinationPort = connection.destinationPort ?? state.destinationPort
            state.network = connection.network ?? state.network
            state.inbound = connection.inbound ?? state.inbound
            state.ruleType = connection.ruleType
            state.rulePayload = connection.rulePayload
            state.chains = connection.chains
            if let process = connection.processName, !process.isEmpty {
                state.processes.insert(process)
            }
            state.download += downDelta
            state.upload += upDelta
            state.lastSeen = now
            activeByKey[key, default: 0] += 1
            rateDownByKey[key, default: 0] += Double(downDelta) / elapsed
            rateUpByKey[key, default: 0] += Double(upDelta) / elapsed

            let exitName = connection.chains.count > 1
                ? connection.chains.last
                : nil
            let nodeName = connection.chains.first
            let variantID = [
                connection.ruleType,
                connection.rulePayload,
                exitName ?? "",
                nodeName ?? ""
            ].joined(separator: "|")
            if var variant = state.variants[variantID] {
                variant = ClashLiveVariant(
                    ruleType: variant.ruleType,
                    rulePayload: variant.rulePayload,
                    exitName: variant.exitName,
                    nodeName: variant.nodeName,
                    count: variant.count + 1
                )
                state.variants[variantID] = variant
            } else {
                state.variants[variantID] = ClashLiveVariant(
                    ruleType: connection.ruleType,
                    rulePayload: connection.rulePayload,
                    exitName: exitName,
                    nodeName: nodeName,
                    count: 1
                )
            }
            states[key] = state
        }

        ledger = nextLedger

        for key in states.keys {
            guard var state = states[key] else { continue }
            let active = activeByKey[key] ?? 0
            state.active = active
            let downRate = rateDownByKey[key] ?? 0
            let upRate = rateUpByKey[key] ?? 0
            if active > 0 {
                state.downloadRate = state.downloadRate * 0.45 + downRate * 0.55
                state.uploadRate = state.uploadRate * 0.45 + upRate * 0.55
            } else {
                state.downloadRate *= 0.35
                state.uploadRate *= 0.35
                if state.downloadRate < 1 { state.downloadRate = 0 }
                if state.uploadRate < 1 { state.uploadRate = 0 }
            }
            states[key] = state
        }

        let cutoff = now.addingTimeInterval(-600)
        states = states.filter { _, state in
            state.active > 0 || state.lastSeen >= cutoff
        }

        return states.values.compactMap { state in
            guard state.count > 0 else { return nil }
            let variants = state.variants.values.sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.id < $1.id
            }
            let currentVariant = variants.first
            return ClashLiveDomain(
                id: state.host.lowercased(),
                host: state.host,
                isIP: state.isIP,
                destinationIP: state.destinationIP,
                destinationPort: state.destinationPort,
                network: state.network,
                inbound: state.inbound,
                ruleType: currentVariant?.ruleType ?? state.ruleType,
                rulePayload: currentVariant?.rulePayload ?? state.rulePayload,
                chains: state.chains,
                exitName: currentVariant?.exitName,
                nodeName: currentVariant?.nodeName,
                processNames: state.processes.sorted(),
                download: state.download,
                upload: state.upload,
                downloadRate: state.downloadRate,
                uploadRate: state.uploadRate,
                activeConnections: state.active,
                connectionCount: state.count,
                firstSeen: state.firstSeen,
                lastSeen: state.lastSeen,
                variants: Array(variants.prefix(6))
            )
        }
        .sorted {
            if $0.activeConnections != $1.activeConnections {
                return $0.activeConnections > $1.activeConnections
            }
            return $0.lastSeen > $1.lastSeen
        }
    }
}

public struct ClashLiveService: Sendable {
    public init() {}

    public func connections(socket: URL) async throws -> [ClashLiveConnection] {
        let response = try await UnixHTTPClient.get(
            socketPath: socket.path,
            path: "/connections"
        )
        let object = try jsonObject(response.body)
        let rows = object["connections"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let metadata = row["metadata"] as? [String: Any] ?? [:]
            let host = firstNonEmpty(
                metadata["host"] as? String,
                metadata["sniffHost"] as? String,
                metadata["destinationIP"] as? String,
                metadata["remoteDestination"] as? String
            ) ?? "未知目标"
            let chains = (row["chains"] as? [String] ?? []).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let processPath = firstNonEmpty(
                metadata["processPath"] as? String,
                metadata["process"] as? String
            )
            let processName = firstNonEmpty(
                metadata["process"] as? String,
                processPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            )
            return ClashLiveConnection(
                id: id,
                host: host,
                destinationIP: firstNonEmpty(
                    metadata["destinationIP"] as? String,
                    metadata["remoteDestination"] as? String
                ),
                destinationPort: metadata["destinationPort"] as? String,
                network: metadata["network"] as? String,
                inbound: metadata["inboundName"] as? String,
                ruleType: Self.normalizeRuleType(row["rule"] as? String),
                rulePayload: row["rulePayload"] as? String ?? "",
                chains: chains,
                download: Self.int64(row["download"]),
                upload: Self.int64(row["upload"]),
                start: row["start"] as? String,
                processName: processName,
                processPath: processPath
            )
        }
    }

    public func proxies(socket: URL) async throws -> ClashProxySnapshot {
        let response = try await UnixHTTPClient.get(
            socketPath: socket.path,
            path: "/proxies"
        )
        return try Self.parseProxies(response.body)
    }

    public static func parseProxies(_ data: Data) throws -> ClashProxySnapshot {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            throw ClashLiveError.invalidResponse("缺少 proxies 对象")
        }
        let proxies = object["proxies"] as? [String: [String: Any]] ?? [:]
        let groupTypes = Set([
            "Selector", "URLTest", "Fallback", "LoadBalance",
            "Select", "Relay"
        ])
        var groups: [ClashLiveProxyGroup] = []
        for (name, value) in proxies {
            guard let type = value["type"] as? String,
                  let all = value["all"] as? [String],
                  groupTypes.contains(type) else {
                continue
            }
            let history = value["history"] as? [[String: Any]] ?? []
            let delay = history.last.flatMap { item -> Int? in
                let value = Self.int64(item["delay"])
                return value > 0 ? Int(value) : nil
            }
            let members = all.compactMap { memberName -> ClashLiveProxyMember? in
                let member = proxies[memberName]
                return ClashLiveProxyMember(
                    name: memberName,
                    type: member?["type"] as? String ?? "Unknown",
                    delay: Self.proxyDelay(member)
                )
            }
            groups.append(
                ClashLiveProxyGroup(
                    name: name,
                    type: type,
                    selected: value["now"] as? String,
                    memberCount: all.count,
                    delay: delay,
                    members: members
                )
            )
        }
        groups.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return ClashProxySnapshot(
            groups: groups,
            targetNames: Set(proxies.keys)
        )
    }

    private static func proxyDelay(_ proxy: [String: Any]?) -> Int? {
        guard let history = proxy?["history"] as? [[String: Any]],
              let item = history.last else {
            return nil
        }
        let delay = Self.int64(item["delay"])
        return delay > 0 ? Int(delay) : nil
    }

    public func rules(socket: URL) async throws -> [ClashLiveRule] {
        let response = try await UnixHTTPClient.get(
            socketPath: socket.path,
            path: "/rules"
        )
        let object = try jsonObject(response.body)
        let rows = object["rules"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let index = row["index"] as? Int else { return nil }
            let type = Self.normalizeRuleType(row["type"] as? String)
            let payload = row["payload"] as? String ?? ""
            let target = row["proxy"] as? String ?? ""
            let extra = row["extra"] as? [String: Any] ?? [:]
            return ClashLiveRule(
                id: "\(index)|\(type)|\(payload)|\(target)",
                index: index,
                type: type,
                payload: payload,
                target: target,
                hitCount: Int(Self.int64(extra["hitCount"])),
                missCount: Int(Self.int64(extra["missCount"])),
                disabled: extra["disabled"] as? Bool ?? false
            )
        }
    }

    public func ruleProviders(socket: URL) async throws -> [ClashLiveRuleProvider] {
        let response = try await UnixHTTPClient.get(
            socketPath: socket.path,
            path: "/providers/rules"
        )
        let object = try jsonObject(response.body)
        let providers = object["providers"] as? [String: [String: Any]] ?? [:]
        return providers.map { name, value in
            ClashLiveRuleProvider(
                name: name,
                behavior: value["behavior"] as? String ?? "",
                format: value["format"] as? String ?? "",
                vehicleType: value["vehicleType"] as? String ?? "",
                ruleCount: Int(Self.int64(value["ruleCount"])),
                updatedAt: value["updatedAt"] as? String
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func selectProxyMember(
        socket: URL,
        group: String,
        member: String
    ) async throws {
        _ = try await UnixHTTPClient.put(
            socketPath: socket.path,
            path: "/proxies/\(pathComponent(group))",
            jsonBody: ["name": member]
        )
    }

    public func refreshRuleProvider(socket: URL, name: String) async throws {
        _ = try await UnixHTTPClient.put(
            socketPath: socket.path,
            path: "/providers/rules/\(pathComponent(name))",
            jsonBody: [:]
        )
    }

    public static func normalizeRuleType(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "UNKNOWN" }
        let mapping = [
            "Domain": "DOMAIN",
            "DomainSuffix": "DOMAIN-SUFFIX",
            "DomainKeyword": "DOMAIN-KEYWORD",
            "DomainRegex": "DOMAIN-REGEX",
            "DomainWildcard": "DOMAIN-WILDCARD",
            "GeoSite": "GEOSITE",
            "GeoIP": "GEOIP",
            "IPCIDR": "IP-CIDR",
            "IPCIDR6": "IP-CIDR6",
            "SrcIPCIDR": "SRC-IP-CIDR",
            "ProcessName": "PROCESS-NAME",
            "ProcessPath": "PROCESS-PATH",
            "RuleSet": "RULE-SET",
            "Match": "MATCH",
            "DstPort": "DST-PORT",
            "SrcPort": "SRC-PORT",
            "Network": "NETWORK",
            "InPort": "IN-PORT"
        ]
        if let mapped = mapping[raw] { return mapped }
        return raw
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1-$2",
                options: .regularExpression
            )
            .uppercased()
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
            throw ClashLiveError.invalidResponse("不是 JSON 对象")
        }
        return object
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.first {
            guard let value = $0 else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }

    private func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? value
    }
}

private func normalizeRuleType(_ raw: String?) -> String {
    ClashLiveService.normalizeRuleType(raw)
}

private func isIPAddress(_ value: String) -> Bool {
    var address = in6_addr()
    if value.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 {
        return true
    }
    var ipv4 = in_addr()
    return value.withCString { inet_pton(AF_INET, $0, &ipv4) } == 1
}
