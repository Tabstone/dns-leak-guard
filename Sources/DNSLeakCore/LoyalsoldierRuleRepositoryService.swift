import Foundation

public enum LoyalsoldierRuleRepositoryError: LocalizedError {
    case invalidResponse(String)
    case http(Int, String)
    case rateLimited
    case missingData(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidResponse(message):
            "规则仓库返回无法解析的数据：\(message)"
        case let .http(code, message):
            "规则仓库 HTTP \(code)：\(message)"
        case .rateLimited:
            "GitHub 请求次数受限，请稍后重试。"
        case let .missingData(field):
            "规则仓库数据缺少字段：\(field)"
        }
    }
}

public struct LoyalsoldierRuleRepositorySnapshot: Codable, Sendable {
    public let repositoryName: String
    public let description: String
    public let repositoryURL: String
    public let defaultBranch: String
    public let stars: Int
    public let pushedAt: String?
    public let releaseBranch: String
    public let releaseCommitSHA: String
    public let releaseCommitMessage: String
    public let releaseCommitDate: String?
    public let releaseCommitURL: String?
    public let privateRuleCount: Int
    public let directRuleCount: Int
    public let proxyRuleCount: Int
    public let readme: String?
    public let fetchedAt: Date

    public init(
        repositoryName: String,
        description: String,
        repositoryURL: String,
        defaultBranch: String,
        stars: Int,
        pushedAt: String?,
        releaseBranch: String,
        releaseCommitSHA: String,
        releaseCommitMessage: String,
        releaseCommitDate: String?,
        releaseCommitURL: String?,
        privateRuleCount: Int,
        directRuleCount: Int,
        proxyRuleCount: Int,
        readme: String?,
        fetchedAt: Date = Date()
    ) {
        self.repositoryName = repositoryName
        self.description = description
        self.repositoryURL = repositoryURL
        self.defaultBranch = defaultBranch
        self.stars = stars
        self.pushedAt = pushedAt
        self.releaseBranch = releaseBranch
        self.releaseCommitSHA = releaseCommitSHA
        self.releaseCommitMessage = releaseCommitMessage
        self.releaseCommitDate = releaseCommitDate
        self.releaseCommitURL = releaseCommitURL
        self.privateRuleCount = privateRuleCount
        self.directRuleCount = directRuleCount
        self.proxyRuleCount = proxyRuleCount
        self.readme = readme
        self.fetchedAt = fetchedAt
    }

    public var shortCommitSHA: String {
        String(releaseCommitSHA.prefix(10))
    }

    public var ruleCountLabel: String {
        "private \(privateRuleCount) · direct \(directRuleCount) · proxy \(proxyRuleCount)"
    }

    public var readmeExcerpt: String {
        guard let readme else { return "" }
        let visible = readme
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return !line.isEmpty
                    && !line.hasPrefix("<")
                    && !line.hasPrefix("![")
                    && !line.hasPrefix("```")
            }
            .prefix(8)
            .joined(separator: "\n")
        return extractedText(from: visible)
    }

    private func extractedText(from markdown: String) -> String {
        markdown
            .replacingOccurrences(
                of: #"!\[[^\]]*\]\([^)]+\)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\[([^\]]+)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[*_`#]+"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct LoyalsoldierRuleRepositorySyncReport: Sendable {
    public let directory: URL
    public let files: [URL]
    public let snapshot: LoyalsoldierRuleRepositorySnapshot
    public let syncedAt: Date

    public init(
        directory: URL,
        files: [URL],
        snapshot: LoyalsoldierRuleRepositorySnapshot,
        syncedAt: Date = Date()
    ) {
        self.directory = directory
        self.files = files
        self.snapshot = snapshot
        self.syncedAt = syncedAt
    }
}

public struct LoyalsoldierRuleRepositoryService: Sendable {
    public static let repository = "Loyalsoldier/clash-rules"
    public static let repositoryURL = URL(
        string: "https://github.com/Loyalsoldier/clash-rules"
    )!
    public static let releaseBranch = "release"
    public static let ruleFiles = ["private.txt", "direct.txt", "proxy.txt"]

    private let session: URLSession
    private let cacheDirectory: URL

    public init(
        session: URLSession? = nil,
        cacheDirectory: URL? = nil
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 45
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpAdditionalHeaders = [
                "User-Agent": "DNSLeakGuard/1.0"
            ]
            self.session = URLSession(configuration: configuration)
        }
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory
    }

    public func fetch() async throws -> LoyalsoldierRuleRepositorySnapshot {
        async let repositoryPageData = optionalRequest(
            URL(string: "https://github.com/\(Self.repository)")!
        )
        async let commitFeedData = request(
            URL(
                string: "https://github.com/\(Self.repository)/commits/\(Self.releaseBranch).atom"
            )!
        )
        async let readmeData = optionalRequest(
            URL(string: "https://raw.githubusercontent.com/\(Self.repository)/master/README.md")!
        )
        async let privateData = request(
            ruleURL("private.txt")
        )
        async let directData = request(
            ruleURL("direct.txt")
        )
        async let proxyData = request(
            ruleURL("proxy.txt")
        )

        let repositoryPage = try await repositoryPageData
        let commitFeed = try await commitFeedData
        let readme = try await readmeData
        let privateRules = try await privateData
        let directRules = try await directData
        let proxyRules = try await proxyData

        let page = repositoryPage.flatMap {
            String(data: $0, encoding: .utf8)
        } ?? ""
        let commit = try parseCommitFeed(commitFeed)
        let description = firstMatch(
            in: page,
            pattern: #"<meta\s+name="description"\s+content="([^"]*)""#
        ).map(decodeHTMLEntities) ?? ""
        let stars = Int(
            firstMatch(
                in: page,
                pattern: #""stargazerCount"\s*:\s*(\d+)"#
            ) ?? ""
        ) ?? 0
        let defaultBranch = firstMatch(
            in: page,
            pattern: #""defaultBranch"\s*:\s*"([^"]+)""#
        ) ?? "master"

        return LoyalsoldierRuleRepositorySnapshot(
            repositoryName: Self.repository,
            description: description
                .replacingOccurrences(
                    of: " - \(Self.repository)",
                    with: ""
                ),
            repositoryURL: Self.repositoryURL.absoluteString,
            defaultBranch: defaultBranch,
            stars: stars,
            pushedAt: commit.updated,
            releaseBranch: Self.releaseBranch,
            releaseCommitSHA: commit.sha,
            releaseCommitMessage: commit.message,
            releaseCommitDate: commit.updated,
            releaseCommitURL: commit.url,
            privateRuleCount: countRuleEntries(privateRules),
            directRuleCount: countRuleEntries(directRules),
            proxyRuleCount: countRuleEntries(proxyRules),
            readme: readme.flatMap { String(data: $0, encoding: .utf8) }
        )
    }

    public func sync(
        snapshot: LoyalsoldierRuleRepositorySnapshot
    ) async throws -> LoyalsoldierRuleRepositorySyncReport {
        let fileManager = FileManager.default
        let rulesDirectory = cacheDirectory.appendingPathComponent(
            "rules",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: rulesDirectory,
            withIntermediateDirectories: true
        )

        async let privateData = request(ruleURL("private.txt"))
        async let directData = request(ruleURL("direct.txt"))
        async let proxyData = request(ruleURL("proxy.txt"))
        let downloaded = [
            "private.txt": try await privateData,
            "direct.txt": try await directData,
            "proxy.txt": try await proxyData
        ]

        var files: [URL] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let snapshotURL = cacheDirectory.appendingPathComponent("snapshot.json")
        try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
        files.append(snapshotURL)

        if let readme = snapshot.readme {
            let readmeURL = cacheDirectory.appendingPathComponent("README.md")
            try Data(readme.utf8).write(to: readmeURL, options: .atomic)
            files.append(readmeURL)
        }

        for name in Self.ruleFiles {
            guard let data = downloaded[name] else { continue }
            let url = rulesDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            files.append(url)
        }

        return LoyalsoldierRuleRepositorySyncReport(
            directory: cacheDirectory,
            files: files,
            snapshot: snapshot
        )
    }

    public func loadCachedSnapshot() throws -> LoyalsoldierRuleRepositorySnapshot? {
        let url = cacheDirectory.appendingPathComponent("snapshot.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            LoyalsoldierRuleRepositorySnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    public var cachePath: String {
        cacheDirectory.path
    }

    private func ruleURL(_ file: String) -> URL {
        URL(
            string: "https://raw.githubusercontent.com/\(Self.repository)/\(Self.releaseBranch)/\(file)"
        )!
    }

    private func countRuleEntries(_ data: Data) -> Int {
        guard let text = String(data: data, encoding: .utf8) else { return 0 }
        return text
            .split(whereSeparator: \.isNewline)
            .reduce(into: 0) { count, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty,
                      line != "payload:",
                      !line.hasPrefix("#") else {
                    return
                }
                count += 1
            }
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "application/atom+xml,text/html;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "DNSLeakGuard/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LoyalsoldierRuleRepositoryError.invalidResponse("不是 HTTP 响应")
        }
        if http.statusCode == 403 || http.statusCode == 429 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.localizedCaseInsensitiveContains("rate limit") {
                throw LoyalsoldierRuleRepositoryError.rateLimited
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoyalsoldierRuleRepositoryError.http(
                http.statusCode,
                String(body.prefix(280))
            )
        }
        return data
    }

    private func optionalRequest(_ url: URL) async throws -> Data? {
        do {
            return try await request(url)
        } catch let error as LoyalsoldierRuleRepositoryError {
            if case let .http(code, _) = error, code == 404 {
                return nil
            }
            throw error
        }
    }

    private struct CommitFeedEntry {
        let sha: String
        let message: String
        let updated: String?
        let url: String?
    }

    private func parseCommitFeed(_ data: Data) throws -> CommitFeedEntry {
        guard let text = String(data: data, encoding: .utf8),
              let entryStart = text.range(of: "<entry>")?.lowerBound else {
            throw LoyalsoldierRuleRepositoryError.invalidResponse(
                "提交 Atom 中没有 entry"
            )
        }
        let entry = String(text[entryStart...])
        guard let sha = firstMatch(
            in: entry,
            pattern: #"<id>[^<]*Grit::Commit/([0-9a-f]{7,40})</id>"#
        ) else {
            throw LoyalsoldierRuleRepositoryError.missingData("commit.sha")
        }
        let rawTitle = firstMatch(
            in: entry,
            pattern: #"<title>\s*([\s\S]*?)\s*</title>"#
        ) ?? ""
        let message = decodeHTMLEntities(rawTitle)
            .split(separator: "\n")
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""
        return CommitFeedEntry(
            sha: sha,
            message: message,
            updated: firstMatch(
                in: entry,
                pattern: #"<updated>([^<]+)</updated>"#
            ),
            url: "https://github.com/\(Self.repository)/commit/\(sha)"
        )
    }

    private func firstMatch(
        in text: String,
        pattern: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let searchRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(
            in: text,
            range: searchRange
        ), match.numberOfRanges > 1,
        let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static var defaultCacheDirectory: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return root
            .appendingPathComponent("DNSLeakGuard", isDirectory: true)
            .appendingPathComponent("Upstream", isDirectory: true)
            .appendingPathComponent("Loyalsoldier-clash-rules", isDirectory: true)
    }
}
