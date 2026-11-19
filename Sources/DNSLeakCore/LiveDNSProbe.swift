import Foundation

public enum LiveDNSProbe {
    public static func run() async -> LiveDNSTestResult {
        let session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 18
            configuration.timeoutIntervalForResource = 24
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "DNSLeakGuard/1.0"
            ]
            return URLSession(configuration: configuration)
        }()
        defer { session.invalidateAndCancel() }

        let attempts = 12
        var observations: [DNSObservation] = []
        var successes = 0

        await withTaskGroup(of: [DNSObservation]?.self) { group in
            for index in 0..<attempts {
                group.addTask {
                    let family = index.isMultiple(of: 2) ? "dns4" : "dns6"
                    let suffix = index < 4 ? "net" : "org"
                    let subdomain = "\(randomToken(length: 12)).\(family).browserleaks.\(suffix)"
                    guard let url = URL(string: "https://\(subdomain)/") else {
                        return nil
                    }
                    do {
                        let (data, response) = try await session.data(from: url)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200 else {
                            return nil
                        }
                        return parseObservations(data)
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

        var byIP: [String: DNSObservation] = [:]
        for observation in observations {
            byIP[observation.ip] = observation
        }
        let unique = byIP.values.sorted {
            $0.ip.localizedStandardCompare($1.ip) == .orderedAscending
        }
        if unique.isEmpty {
            return LiveDNSTestResult(
                observations: [],
                queriesSucceeded: successes,
                queriesAttempted: attempts,
                outcome: .error,
                message: successes == 0
                    ? "在线探测请求全部失败；可能是网络、系统代理或测试端点暂时不可用。"
                    : "探测请求成功，但端点没有返回解析器身份。"
            )
        }

        let isps = Array(Set(unique.map(\.isp))).sorted()
        let locations = Array(Set(unique.map(\.location))).sorted()
        let multiple = isps.count > 1 || locations.count > 1
        let message: String
        if multiple {
            message = "发现 \(isps.count) 个 ISP、\(locations.count) 个地区。多解析器路径可能是泄露，也可能来自多出口或 anycast；请结合配置风险和 BrowserLeaks 页面复验。"
        } else {
            message = "发现 \(unique.count) 个解析器地址，均属于 \(isps.first ?? "未知 ISP") / \(locations.first ?? "未知地区")。未观察到多解析器路径。"
        }
        return LiveDNSTestResult(
            observations: unique,
            queriesSucceeded: successes,
            queriesAttempted: attempts,
            outcome: multiple ? .multipleResolverPaths : .singleResolverPath,
            message: message
        )
    }

    public static func parseObservations(_ data: Data) -> [DNSObservation] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            return []
        }
        return object.compactMap { ip, values in
            guard values.count >= 3 else { return nil }
            return DNSObservation(
                ip: ip,
                countryCode: values[0],
                location: values[1],
                isp: values[2]
            )
        }
    }

    private static func randomToken(length: Int) -> String {
        let characters = Array("abcdefghijkmnopqrstuvwyz0123456789")
        return String((0..<length).map { _ in
            characters[Int.random(in: 0..<characters.count)]
        })
    }
}
