import Darwin
import Foundation

public enum DNSLeakProviderID: String, CaseIterable, Identifiable, Sendable {
    case browserLeaks = "browserleaks"
    case dnsLeakTest = "dnsleaktest"
    case ipLeak = "ipleak"
    case browserScan = "browserscan"
    case ip125 = "ip125"
    case ipCheck = "ipcheck"
    case whoer = "whoer"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .browserLeaks: "BrowserLeaks"
        case .dnsLeakTest: "DNSLeakTest"
        case .ipLeak: "IPLeak"
        case .browserScan: "BrowserScan"
        case .ip125: "IP125"
        case .ipCheck: "IPCheck.ing"
        case .whoer: "Whoer"
        }
    }

    public var shortTitle: String {
        switch self {
        case .browserLeaks: "BrowserLeaks"
        case .dnsLeakTest: "DNSLeakTest"
        case .ipLeak: "IPLeak"
        case .browserScan: "BrowserScan"
        case .ip125: "IP125"
        case .ipCheck: "IPCheck"
        case .whoer: "Whoer"
        }
    }

    public var pageURL: URL {
        switch self {
        case .browserLeaks:
            URL(string: "https://browserleaks.com/dns")!
        case .dnsLeakTest:
            URL(string: "https://www.dnsleaktest.com/")!
        case .ipLeak:
            URL(string: "https://ipleak.net/")!
        case .browserScan:
            URL(string: "https://www.browserscan.net/zh/dns-leak")!
        case .ip125:
            URL(string: "https://ip125.com/leak-test/")!
        case .ipCheck:
            URL(string: "https://ipcheck.ing/#/")!
        case .whoer:
            URL(string: "https://whoer.net/zh/dns-leak-test")!
        }
    }

    public var integration: DNSLeakProviderIntegration {
        switch self {
        case .browserLeaks, .dnsLeakTest, .ipLeak:
            .nativeAPI
        case .browserScan, .ip125:
            .pageSource
        case .ipCheck:
            .openSourceMirror
        case .whoer:
            .webOnly
        }
    }

    public var methodDescription: String {
        switch self {
        case .browserLeaks:
            "同源随机子域；返回解析器 IP、地区与 ISP。"
        case .dnsLeakTest:
            "官方 /api/v1 会话接口；随机 UUID 探测后读取解析器列表。"
        case .ipLeak:
            "同源随机会话子域 /dnsdetection/；解析器 IP 再补地理信息。"
        case .browserScan:
            "按页面源码复刻 IP-API EDNS 与 Surfshark DNS 两条探测链。"
        case .ip125:
            "按 /leak-test 页面源码复刻其 IP-API、Surfshark 与 IPLeak 聚合链。"
        case .ipCheck:
            "官方 API 当前被 Cloudflare 拦截；使用其开源 MyIP 引擎同源复刻。"
        case .whoer:
            "Cloudflare Managed Challenge 阻止原生 API；仅提供网页复核。"
        }
    }

    public var isNativeResult: Bool {
        integration != .webOnly
    }
}

public enum DNSLeakProviderIntegration: String, Sendable {
    case nativeAPI
    case pageSource
    case openSourceMirror
    case webOnly

    public var label: String {
        switch self {
        case .nativeAPI: "官方 API"
        case .pageSource: "页面同源"
        case .openSourceMirror: "开源镜像"
        case .webOnly: "仅网页"
        }
    }
}

public enum DNSLeakProviderOutcome: String, Sendable {
    case clean
    case multiplePaths
    case inconclusive
    case unsupported
    case failed

    public var label: String {
        switch self {
        case .clean: "单一路径"
        case .multiplePaths: "多路径"
        case .inconclusive: "无法判定"
        case .unsupported: "需网页复核"
        case .failed: "检测失败"
        }
    }
}

public struct DNSLeakProviderResult: Identifiable, Sendable {
    public let provider: DNSLeakProviderID
    public let observations: [DNSObservation]
    public let queriesSucceeded: Int
    public let queriesAttempted: Int
    public let outcome: DNSLeakProviderOutcome
    public let message: String
    public let method: String
    public let testedAt: Date

    public var id: DNSLeakProviderID { provider }

    public init(
        provider: DNSLeakProviderID,
        observations: [DNSObservation],
        queriesSucceeded: Int,
        queriesAttempted: Int,
        outcome: DNSLeakProviderOutcome,
        message: String,
        method: String,
        testedAt: Date = Date()
    ) {
        self.provider = provider
        self.observations = observations
        self.queriesSucceeded = queriesSucceeded
        self.queriesAttempted = queriesAttempted
        self.outcome = outcome
        self.message = message
        self.method = method
        self.testedAt = testedAt
    }

    public var resolverCount: Int {
        Set(observations.map(\.ip)).count
    }
}

public enum DNSLeakProviders {
    public static func run(
        provider: DNSLeakProviderID
    ) async -> DNSLeakProviderResult {
        switch provider {
        case .browserLeaks:
            return await runBrowserLeaks()
        case .dnsLeakTest:
            return await runDNSLeakTest()
        case .ipLeak:
            return await runIPLeak()
        case .browserScan:
            return await runBrowserScan()
        case .ip125:
            return await runIP125()
        case .ipCheck:
            return await runIPCheckMirror()
        case .whoer:
            return DNSLeakProviderResult(
                provider: .whoer,
                observations: [],
                queriesSucceeded: 0,
                queriesAttempted: 0,
                outcome: .unsupported,
                message: "Whoer 的页面与 API 当前均返回 Cloudflare 403。工具不会伪造结果；请点击网页复核，在浏览器中完成挑战后查看。",
                method: provider.methodDescription
            )
        }
    }

    public static func parseIPLeak(_ data: Data) -> [DNSObservation] {
        guard let object = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
              let map = object["ip"] as? [String: Any] else {
            return []
        }
        return map.keys
            .filter(isUsableResolverAddress)
            .sorted()
            .map {
                DNSObservation(
                    ip: $0,
                    countryCode: "",
                    location: "",
                    isp: ""
                )
            }
    }

    public static func parseDNSLeakTest(_ data: Data) -> [DNSObservation] {
        guard let rows = try? JSONSerialization.jsonObject(with: data)
            as? [[String: Any]] else {
            return []
        }
        return rows.compactMap { row in
            guard let ip = row["ip_address"] as? String,
                  isUsableResolverAddress(ip) else {
                return nil
            }
            let city = row["city"] as? String ?? ""
            let country = row["country"] as? String ?? ""
            let location = [city, country]
                .filter { !$0.isEmpty && $0 != "None" }
                .joined(separator: ", ")
            return DNSObservation(
                ip: ip,
                countryCode: (row["country_code"] as? String ?? "").uppercased(),
                location: location,
                isp: row["isp"] as? String ?? row["organization"] as? String ?? ""
            )
        }
    }

    public static func parseSurfshark(_ data: Data) -> [DNSObservation] {
        guard let object = try? JSONSerialization.jsonObject(with: data)
            as? [String: [String: Any]] else {
            return []
        }
        var byIP: [String: DNSObservation] = [:]
        for values in object.values {
            guard let ip = values["IP"] as? String,
                  isUsableResolverAddress(ip) else { continue }
            let city = values["City"] as? String ?? ""
            let country = values["Country"] as? String ?? ""
            byIP[ip] = DNSObservation(
                ip: ip,
                countryCode: (values["CountryCode"] as? String ?? "").uppercased(),
                location: [city, country]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", "),
                isp: values["ISP"] as? String ?? ""
            )
        }
        return byIP.values.sorted {
            $0.ip.localizedStandardCompare($1.ip) == .orderedAscending
        }
    }

    private static func runBrowserLeaks() async -> DNSLeakProviderResult {
        let session = makeSession(timeout: 12)
        defer { session.invalidateAndCancel() }
        let attempts = 10
        var observations: [DNSObservation] = []
        var successes = 0

        await withTaskGroup(of: [DNSObservation]?.self) { group in
            for index in 0..<attempts {
                group.addTask {
                    let family = index.isMultiple(of: 2) ? "dns4" : "dns6"
                    let suffix = index < 4 ? "net" : "org"
                    let host = "\(token(length: 12)).\(family).browserleaks.\(suffix)"
                    guard let url = URL(string: "https://\(host)/") else {
                        return nil
                    }
                    do {
                        let (data, response) = try await session.data(from: url)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200 else {
                            return nil
                        }
                        return LiveDNSProbe.parseObservations(data)
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                guard let result, !result.isEmpty else { continue }
                successes += 1
                observations.append(contentsOf: result)
            }
        }

        return finish(
            provider: .browserLeaks,
            observations: observations,
            succeeded: successes,
            attempted: attempts,
            emptyMessage: "随机子域请求未返回解析器身份；请检查当前代理是否拦截 browserleaks.net。"
        )
    }

    private static func runDNSLeakTest() async -> DNSLeakProviderResult {
        let session = makeSession(timeout: 12)
        defer { session.invalidateAndCancel() }
        let identifiers = (0..<6).map { _ in UUID().uuidString.lowercased() }
        let base = URL(string: "https://www.dnsleaktest.com")!
        var successes = 0
        var resultError: Error?

        do {
            var register = URLRequest(
                url: base.appendingPathComponent("api/v1/identifiers")
            )
            register.httpMethod = "POST"
            register.setValue("application/json", forHTTPHeaderField: "Content-Type")
            register.setValue(
                "https://www.dnsleaktest.com/results.html",
                forHTTPHeaderField: "Referer"
            )
            register.httpBody = try JSONSerialization.data(
                withJSONObject: ["identifiers": identifiers]
            )
            let (_, response) = try await session.data(for: register)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ProviderError.message("DNSLeakTest 会话注册被拒绝。")
            }

            await withTaskGroup(of: Bool.self) { group in
                for identifier in identifiers {
                    group.addTask {
                        guard let url = URL(
                            string: "http://\(identifier).test.dnsleaktest.com/"
                        ) else {
                            return false
                        }
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 7
                        do {
                            _ = try await session.data(for: request)
                            return true
                        } catch {
                            // DNS resolution happens before TLS/HTTP errors. The
                            // server-side result endpoint is authoritative.
                            return false
                        }
                    }
                }
                for await ok in group where ok {
                    successes += 1
                }
            }

            try await Task.sleep(nanoseconds: 900_000_000)
            var resultRequest = URLRequest(
                url: base.appendingPathComponent("api/v1/servers-for-result")
            )
            resultRequest.httpMethod = "POST"
            resultRequest.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            resultRequest.setValue(
                "https://www.dnsleaktest.com/results.html",
                forHTTPHeaderField: "Referer"
            )
            resultRequest.httpBody = try JSONSerialization.data(
                withJSONObject: ["queries": identifiers]
            )
            let (data, resultResponse) = try await session.data(for: resultRequest)
            guard (resultResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw ProviderError.message("DNSLeakTest 结果接口返回异常。")
            }
            let observations = parseDNSLeakTest(data)
            return finish(
                provider: .dnsLeakTest,
                observations: observations,
                succeeded: max(successes, observations.isEmpty ? 0 : 1),
                attempted: identifiers.count,
                emptyMessage: "DNSLeakTest 未返回解析器；可能被当前代理规则拦截。"
            )
        } catch {
            resultError = error
        }

        return DNSLeakProviderResult(
            provider: .dnsLeakTest,
            observations: [],
            queriesSucceeded: successes,
            queriesAttempted: identifiers.count,
            outcome: .failed,
            message: "DNSLeakTest 检测失败：\(resultError?.localizedDescription ?? "未知错误")",
            method: DNSLeakProviderID.dnsLeakTest.methodDescription
        )
    }

    private static func runIPLeak() async -> DNSLeakProviderResult {
        let collected = await collectIPLeak(count: 7)
        let observations = await enrich(collected.observations)
        return finish(
            provider: .ipLeak,
            observations: observations,
            succeeded: collected.successes,
            attempted: collected.attempts,
            emptyMessage: "IPLeak 随机会话未返回解析器；请检查 ipleak.net 是否被规则拦截。"
        )
    }

    private static func runBrowserScan() async -> DNSLeakProviderResult {
        let attempted = 8
        var observations: [DNSObservation] = []
        var successes = 0

        await withTaskGroup(of: (Bool, [DNSObservation]).self) { group in
            for _ in 0..<4 {
                group.addTask {
                    await probeEDNS()
                }
                group.addTask {
                    await probeSurfshark()
                }
            }
            for await result in group {
                if result.0 {
                    successes += 1
                }
                observations.append(contentsOf: result.1)
            }
        }

        return finish(
            provider: .browserScan,
            observations: await enrich(observations),
            succeeded: successes,
            attempted: attempted,
            emptyMessage: "BrowserScan 同源探测链未返回解析器。"
        )
    }

    private static func runIP125() async -> DNSLeakProviderResult {
        var observations: [DNSObservation] = []
        var successes = 0
        let attempted = 7

        async let edns = probeEDNS()
        async let ednsAgain = probeEDNS()
        async let surfshark = probeSurfshark()
        async let surfsharkAgain = probeSurfshark()
        async let ipLeak = collectIPLeak(count: 3)

        let probes = await [edns, ednsAgain, surfshark, surfsharkAgain]
        for probe in probes {
            if probe.0 { successes += 1 }
            observations.append(contentsOf: probe.1)
        }
        let leak = await ipLeak
        successes += leak.successes
        observations.append(contentsOf: leak.observations)

        return finish(
            provider: .ip125,
            observations: await enrich(observations),
            succeeded: successes,
            attempted: attempted,
            emptyMessage: "IP125 页面聚合链未返回解析器。"
        )
    }

    private static func runIPCheckMirror() async -> DNSLeakProviderResult {
        var observations: [DNSObservation] = []
        var successes = 0
        let attempted = 8

        await withTaskGroup(of: (Bool, [DNSObservation]).self) { group in
            group.addTask { await probeEDNS() }
            group.addTask { await probeEDNS() }
            group.addTask { await probeEvery1DNS() }
            group.addTask { await probeFastly() }
            group.addTask { await probeMyIPStack() }
            group.addTask { await probeSurfshark() }
            group.addTask { await probeBrowserLeaksSingle() }
            group.addTask { await probeIPLeakSingle(step: 1) }
            for await result in group {
                if result.0 { successes += 1 }
                observations.append(contentsOf: result.1)
            }
        }

        let result = finish(
            provider: .ipCheck,
            observations: await enrich(observations),
            succeeded: successes,
            attempted: attempted,
            emptyMessage: "IPCheck.ing 开源引擎镜像未返回解析器。"
        )
        return DNSLeakProviderResult(
            provider: result.provider,
            observations: result.observations,
            queriesSucceeded: result.queriesSucceeded,
            queriesAttempted: result.queriesAttempted,
            outcome: result.outcome,
            message: "\(result.message) 说明：ipcheck.ing 官方 API 被 Cloudflare 403，本结果由 MyIP 开源探测链在本机复刻，不是网页会话结果。",
            method: result.method,
            testedAt: result.testedAt
        )
    }

    private static func collectIPLeak(
        count: Int
    ) async -> (observations: [DNSObservation], successes: Int, attempts: Int) {
        guard count > 0 else { return ([], 0, 0) }
        let session = makeSession(timeout: 9)
        defer { session.invalidateAndCancel() }
        let sessionToken = token(length: 40)
        var observations: [DNSObservation] = []
        var successes = 0

        await withTaskGroup(of: [DNSObservation]?.self) { group in
            for step in 1...count {
                group.addTask {
                    guard let url = URL(
                        string: "https://\(sessionToken)-\(step).ipleak.net/dnsdetection/"
                    ) else {
                        return nil
                    }
                    do {
                        let (data, response) = try await session.data(from: url)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200 else {
                            return nil
                        }
                        let parsed = parseIPLeak(data)
                        return parsed.isEmpty ? nil : parsed
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                guard let result else { continue }
                successes += 1
                observations.append(contentsOf: result)
            }
        }
        return (deduplicate(observations), successes, count)
    }

    private static func probeEDNS() async -> (Bool, [DNSObservation]) {
        let session = makeSession(timeout: 8)
        defer { session.invalidateAndCancel() }
        let host = "\(token(length: 28)).edns.ip-api.com"
        guard let url = URL(string: "https://\(host)/json?lang=en") else {
            return (false, [])
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let dns = object["dns"] as? [String: Any],
                  let ip = dns["ip"] as? String,
                  !ip.isEmpty else {
                return (false, [])
            }
            return (
                true,
                [
                    DNSObservation(
                        ip: ip,
                        countryCode: "",
                        location: "",
                        isp: dns["geo"] as? String ?? ""
                    )
                ]
            )
        } catch {
            return (false, [])
        }
    }

    private static func probeSurfshark() async -> (Bool, [DNSObservation]) {
        let session = makeSession(timeout: 9)
        defer { session.invalidateAndCancel() }
        let host = "\(token(length: 14)).ipv4.surfsharkdns.com"
        guard let url = URL(string: "https://\(host)") else {
            return (false, [])
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                return (false, [])
            }
            let observations = parseSurfshark(data)
            return (!observations.isEmpty, observations)
        } catch {
            return (false, [])
        }
    }

    private static func probeEvery1DNS() async -> (Bool, [DNSObservation]) {
        let session = makeSession(timeout: 9)
        defer { session.invalidateAndCancel() }
        let host = "\(UUID().uuidString.lowercased()).map.help.every1dns.net"
        guard let url = URL(string: "https://\(host)/") else {
            return (false, [])
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let ip = object["ip"] as? String,
                  !ip.isEmpty else {
                return (false, [])
            }
            return (
                true,
                [DNSObservation(ip: ip, countryCode: "", location: "", isp: "")]
            )
        } catch {
            return (false, [])
        }
    }

    private static func probeFastly() async -> (Bool, [DNSObservation]) {
        let session = makeSession(timeout: 9)
        defer { session.invalidateAndCancel() }
        let host = "\(token(length: 22)).u.fastly-analytics.com"
        guard let url = URL(string: "https://\(host)/debug_resolver") else {
            return (false, [])
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let resolver = object["dns_resolver_info"] as? [String: Any],
                  let ip = resolver["ip"] as? String,
                  !ip.isEmpty else {
                return (false, [])
            }
            return (
                true,
                [DNSObservation(ip: ip, countryCode: "", location: "", isp: "")]
            )
        } catch {
            return (false, [])
        }
    }

    private static func probeMyIPStack() async -> (Bool, [DNSObservation]) {
        let session = makeSession(timeout: 9)
        defer { session.invalidateAndCancel() }
        let label = token(length: 24)
        guard let url = URL(
            string: "https://\(label).dns.myipstack.com/getRemoteAddress?name=\(label)"
        ) else {
            return (false, [])
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let text = String(data: data, encoding: .utf8),
                  let ip = parseRemoteAddress(text) else {
                return (false, [])
            }
            return (
                true,
                [DNSObservation(ip: ip, countryCode: "", location: "", isp: "")]
            )
        } catch {
            return (false, [])
        }
    }

    private static func probeBrowserLeaksSingle() async -> (Bool, [DNSObservation]) {
        let session = makeSession(timeout: 9)
        defer { session.invalidateAndCancel() }
        let host = "\(token(length: 12)).dns4.browserleaks.net"
        guard let url = URL(string: "https://\(host)/") else {
            return (false, [])
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                return (false, [])
            }
            let observations = LiveDNSProbe.parseObservations(data)
            return (!observations.isEmpty, observations)
        } catch {
            return (false, [])
        }
    }

    private static func probeIPLeakSingle(
        step: Int
    ) async -> (Bool, [DNSObservation]) {
        let session = makeSession(timeout: 9)
        defer { session.invalidateAndCancel() }
        let host = "\(token(length: 40))-\(step).ipleak.net"
        guard let url = URL(string: "https://\(host)/dnsdetection/") else {
            return (false, [])
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                return (false, [])
            }
            let observations = parseIPLeak(data)
            return (!observations.isEmpty, observations)
        } catch {
            return (false, [])
        }
    }

    private static func enrich(
        _ observations: [DNSObservation]
    ) async -> [DNSObservation] {
        let unique = deduplicate(observations)
        let missing = unique.filter {
            $0.isp.isEmpty || $0.location.isEmpty || $0.countryCode.isEmpty
        }
        guard !missing.isEmpty else { return unique }

        let session = makeSession(timeout: 7)
        defer { session.invalidateAndCancel() }
        var geo: [String: DNSObservation] = [:]

        await withTaskGroup(of: (String, DNSObservation?).self) { group in
            for observation in missing {
                group.addTask {
                    guard let encoded = observation.ip.addingPercentEncoding(
                        withAllowedCharacters: .urlPathAllowed
                    ),
                    let url = URL(
                        string: "https://api.ip125.com/geo/\(encoded)?lang=zh-CN"
                    ) else {
                        return (observation.ip, nil)
                    }
                    do {
                        let (data, response) = try await session.data(from: url)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200,
                              let object = try JSONSerialization.jsonObject(
                                with: data
                              ) as? [String: Any],
                              object["status"] as? String == "success" else {
                            return (observation.ip, nil)
                        }
                        let city = object["city"] as? String ?? ""
                        let region = object["regionName"] as? String ?? ""
                        let country = object["country"] as? String ?? ""
                        let location = [city, region, country]
                            .filter { !$0.isEmpty }
                            .joined(separator: ", ")
                        let isp = object["isp"] as? String
                            ?? object["org"] as? String
                            ?? ""
                        return (
                            observation.ip,
                            DNSObservation(
                                ip: observation.ip,
                                countryCode: (
                                    object["countryCode"] as? String ?? ""
                                ).uppercased(),
                                location: location,
                                isp: isp
                            )
                        )
                    } catch {
                        return (observation.ip, nil)
                    }
                }
            }
            for await (ip, result) in group {
                if let result {
                    geo[ip] = result
                }
            }
        }

        return unique.map { geo[$0.ip] ?? $0 }
    }

    private static func finish(
        provider: DNSLeakProviderID,
        observations: [DNSObservation],
        succeeded: Int,
        attempted: Int,
        emptyMessage: String
    ) -> DNSLeakProviderResult {
        let unique = deduplicate(observations)
        guard !unique.isEmpty else {
            return DNSLeakProviderResult(
                provider: provider,
                observations: [],
                queriesSucceeded: succeeded,
                queriesAttempted: attempted,
                outcome: succeeded == 0 ? .failed : .inconclusive,
                message: succeeded == 0
                    ? "\(emptyMessage) 请求全部失败。"
                    : "\(emptyMessage) 请求成功但未识别到解析器身份。",
                method: provider.methodDescription
            )
        }
        let isps = Set(unique.map(\.isp).filter { !$0.isEmpty })
        let ispKeys = Set(isps.map(normalizedISP))
        let locations = Set(unique.map(\.location).filter { !$0.isEmpty })
        let countries = Set(
            unique.map(\.countryCode)
                .map { $0.uppercased() }
                .filter { !$0.isEmpty }
        )
        let multiple = ispKeys.count > 1
            || (ispKeys.isEmpty && countries.count > 1)
        let message: String
        if multiple {
            message = "发现 \(unique.count) 个解析器地址、\(isps.count) 个 ISP、\(locations.count) 个地区；存在多解析器路径，需结合代理规则判断。"
        } else {
            let isp = isps.first ?? "未知 ISP"
            let location = locations.first ?? "未知地区"
            message = "发现 \(unique.count) 个解析器地址，归属 \(isp) / \(location)。"
        }
        return DNSLeakProviderResult(
            provider: provider,
            observations: unique,
            queriesSucceeded: succeeded,
            queriesAttempted: attempted,
            outcome: multiple ? .multiplePaths : .clean,
            message: message,
            method: provider.methodDescription
        )
    }

    private static func deduplicate(
        _ observations: [DNSObservation]
    ) -> [DNSObservation] {
        var byIP: [String: DNSObservation] = [:]
        for observation in observations {
            guard isUsableResolverAddress(observation.ip) else { continue }
            if let existing = byIP[observation.ip] {
                if existing.isp.isEmpty, !observation.isp.isEmpty {
                    byIP[observation.ip] = observation
                }
            } else {
                byIP[observation.ip] = observation
            }
        }
        return byIP.values.sorted {
            $0.ip.localizedStandardCompare($1.ip) == .orderedAscending
        }
    }

    private static func normalizedISP(_ value: String) -> String {
        let lower = value.lowercased()
        let aliases: [(needle: String, key: String)] = [
            ("cloudflare", "cloudflare"),
            ("google", "google"),
            ("amazon", "amazon"),
            ("microsoft", "microsoft"),
            ("quad9", "quad9"),
            ("cisco", "cisco"),
            ("opendns", "opendns"),
            ("akamai", "akamai"),
            ("china telecom", "china-telecom"),
            ("chinanet", "china-telecom"),
            ("china unicom", "china-unicom"),
            ("china mobile", "china-mobile"),
            ("cernet", "cernet")
        ]
        if let alias = aliases.first(where: { lower.contains($0.needle) }) {
            return alias.key
        }
        let stopWords: Set<String> = [
            "inc", "llc", "ltd", "limited", "corp", "corporation",
            "co", "company", "group", "network", "networks",
            "communications", "communication", "services", "service",
            "technology", "technologies", "holdings", "the"
        ]
        let tokens = value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        return tokens.joined()
    }

    private static func isUsableResolverAddress(_ value: String) -> Bool {
        let ip = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else { return false }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, ip, &ipv4) == 1 {
            let bytes = withUnsafeBytes(of: ipv4) { Array($0) }
            return bytes[0] != 0 && bytes[0] != 127
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, ip, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
            let unspecified = bytes.allSatisfy { $0 == 0 }
            let loopback = bytes.dropLast().allSatisfy { $0 == 0 }
                && bytes.last == 1
            return !unspecified && !loopback
        }
        return false
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 5
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json,text/plain,*/*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/537.36 (KHTML, like Gecko) "
                + "Chrome/135.0 Safari/537.36"
        ]
        return URLSession(configuration: configuration)
    }

    private static func token(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return String(
            (0..<length).map { _ in
                alphabet[Int.random(in: 0..<alphabet.count, using: &generator)]
            }
        )
    }

    private static func parseRemoteAddress(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.firstIndex(of: ":"),
              let last = trimmed.lastIndex(of: ":"),
              first < last else {
            return nil
        }
        let ip = String(trimmed[trimmed.index(after: first)..<last])
        return ip.isEmpty ? nil : ip
    }
}

private enum ProviderError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(value): value
        }
    }
}
