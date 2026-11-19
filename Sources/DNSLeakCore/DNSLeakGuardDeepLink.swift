import Foundation

public enum DNSLeakGuardSection: String, CaseIterable, Sendable {
    case overview
    case findings
    case liveTests = "live-tests"
    case traffic
    case repair
    case routing
    case protection
    case permissions
}

public enum DNSLeakGuardDeepLink: Equatable, Sendable {
    public static let scheme = "dnsleakguard"

    case navigate(DNSLeakGuardSection)
    case scan
    case onlineTest(providers: [DNSLeakProviderID]?)

    public static func parse(_ url: URL) -> DNSLeakGuardDeepLink? {
        guard url.scheme?.lowercased() == scheme,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }

        let pathComponents = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let host = components.host?.lowercased()
        let route = host?.isEmpty == false ? host! : pathComponents.first
        let remainingPath = host?.isEmpty == false
            ? pathComponents
            : Array(pathComponents.dropFirst())
        guard let route, remainingPath.isEmpty else {
            return nil
        }

        switch route.lowercased() {
        case "overview", "dashboard", "home":
            return .navigate(.overview)
        case "findings", "diagnostics", "diagnosis":
            return .navigate(.findings)
        case "live-tests", "live", "online", "dns-tests":
            return .navigate(.liveTests)
        case "traffic", "connections":
            return .navigate(.traffic)
        case "repair", "fix":
            return .navigate(.repair)
        case "routing", "rules":
            return .navigate(.routing)
        case "protection", "guard":
            return .navigate(.protection)
        case "permissions", "security", "about":
            return .navigate(.permissions)
        case "scan":
            return .scan
        case "online-test":
            let providerValues = providerQueryValues(
                from: components.queryItems ?? []
            )
            if providerValues.isEmpty {
                return .onlineTest(providers: nil)
            }
            guard let providers = parseProviders(providerValues) else {
                return nil
            }
            return .onlineTest(providers: providers)
        default:
            return nil
        }
    }

    public var section: DNSLeakGuardSection? {
        switch self {
        case let .navigate(section):
            section
        case .scan, .onlineTest:
            .liveTests
        }
    }

    private static func providerQueryValues(
        from queryItems: [URLQueryItem]
    ) -> [String] {
        queryItems
            .filter {
                ["provider", "providers"].contains($0.name.lowercased())
            }
            .flatMap { item in
                (item.value ?? "")
                    .split(separator: ",", omittingEmptySubsequences: true)
                    .map(String.init)
            }
    }

    private static func parseProviders(
        _ providerValues: [String]
    ) -> [DNSLeakProviderID]? {
        if providerValues.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare("all") == .orderedSame
        }) {
            return DNSLeakProviderID.allCases
        }

        var selected = Set<DNSLeakProviderID>()
        for value in providerValues {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard let provider = DNSLeakProviderID(rawValue: normalized) else {
                return nil
            }
            selected.insert(provider)
        }
        return DNSLeakProviderID.allCases.filter(selected.contains)
    }
}
