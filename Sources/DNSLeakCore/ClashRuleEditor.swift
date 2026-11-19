import Foundation

public struct EditableClashRule: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var type: String
    public var payload: String
    public var target: String
    public var options: [String]
    public var hitCount: Int
    public var missCount: Int
    public var sourceIndex: Int?

    public var text: String {
        var fields = [type]
        if !payload.isEmpty {
            fields.append(payload)
        }
        fields.append(target)
        fields.append(contentsOf: options)
        return fields.joined(separator: ",")
    }

    public var isTerminalMatch: Bool {
        type == "MATCH" || type == "FINAL"
    }

    public init(
        id: UUID = UUID(),
        type: String,
        payload: String,
        target: String,
        options: [String] = [],
        hitCount: Int = 0,
        missCount: Int = 0,
        sourceIndex: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.target = target
        self.options = options
        self.hitCount = hitCount
        self.missCount = missCount
        self.sourceIndex = sourceIndex
    }

    public init?(raw: String, index: Int? = nil) {
        let fields = Self.fields(raw)
        guard fields.count >= 2 else { return nil }
        let type = ClashLiveService.normalizeRuleType(fields[0])
        if type == "MATCH" || type == "FINAL" {
            self.init(
                type: type,
                payload: "",
                target: fields[1],
                options: Array(fields.dropFirst(2)),
                sourceIndex: index
            )
            return
        }
        guard fields.count >= 3 else { return nil }
        self.init(
            type: type,
            payload: fields[1],
            target: fields[2],
            options: Array(fields.dropFirst(3)),
            sourceIndex: index
        )
    }

    private static func fields(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var singleQuoted = false
        var doubleQuoted = false
        var escaped = false
        for character in raw {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if doubleQuoted, character == "\\" {
                escaped = true
                continue
            }
            if character == "'", !doubleQuoted {
                singleQuoted.toggle()
                continue
            }
            if character == "\"", !singleQuoted {
                doubleQuoted.toggle()
                continue
            }
            if character == ",", !singleQuoted, !doubleQuoted {
                result.append(
                    current.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                current = ""
                continue
            }
            current.append(character)
        }
        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }
}

public struct ClashRuleDocument: Sendable {
    public let activeConfig: URL
    public let originalText: String
    public let rules: [EditableClashRule]

    public init(
        activeConfig: URL,
        originalText: String,
        rules: [EditableClashRule]
    ) {
        self.activeConfig = activeConfig
        self.originalText = originalText
        self.rules = rules
    }
}

public struct ClashRuleValidationIssue: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let message: String
    public let isError: Bool
    public let ruleID: UUID?

    public init(
        message: String,
        isError: Bool,
        ruleID: UUID? = nil
    ) {
        self.id = UUID()
        self.message = message
        self.isError = isError
        self.ruleID = ruleID
    }
}

public struct ClashRuleValidation: Sendable {
    public let text: String
    public let issues: [ClashRuleValidationIssue]

    public var hasErrors: Bool {
        issues.contains(where: \.isError)
    }
}

public struct ClashRuleApplyReport: Sendable {
    public let changed: Bool
    public let backup: URL?
    public let reloadSucceeded: Bool
    public let reloadMessage: String

    public init(
        changed: Bool,
        backup: URL?,
        reloadSucceeded: Bool,
        reloadMessage: String
    ) {
        self.changed = changed
        self.backup = backup
        self.reloadSucceeded = reloadSucceeded
        self.reloadMessage = reloadMessage
    }
}

public struct ClashRuleEditorService: Sendable {
    public static let builtInTargets: Set<String> = [
        "DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE",
        "GLOBAL"
    ]

    public init() {}

    public func load(workspace: WorkspaceInfo) throws -> ClashRuleDocument {
        let text = try String(
            contentsOf: workspace.activeConfig,
            encoding: .utf8
        )
        let source = try YAMLSource(text: text)
        let rules: [EditableClashRule]
        if let section = source.section(named: "rules") {
            rules = section.compactMap { index in
                let line = source.line(index)
                guard line.startsSequenceItem,
                      let token = source.token(
                        from: index,
                        startingAt: line.indent + 1
                      ) else {
                    return nil
                }
                return EditableClashRule(raw: token.value)
            }
        } else {
            rules = []
        }
        return ClashRuleDocument(
            activeConfig: workspace.activeConfig,
            originalText: text,
            rules: rules
        )
    }

    public func prepare(
        document: ClashRuleDocument,
        rules: [EditableClashRule],
        availableTargets: Set<String>
    ) throws -> ClashRuleValidation {
        var issues: [ClashRuleValidationIssue] = []
        if rules.isEmpty {
            issues.append(
                ClashRuleValidationIssue(
                    message: "规则列表为空，至少需要保留一条规则。",
                    isError: true
                )
            )
        }

        let targets = availableTargets.union(Self.builtInTargets)
        var seen = Set<String>()
        var sawMatchIndex: Int?
        for (index, rule) in rules.enumerated() {
            if rule.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(
                    ClashRuleValidationIssue(
                        message: "第 \(index + 1) 条规则缺少类型。",
                        isError: true,
                        ruleID: rule.id
                    )
                )
            }
            if !rule.isTerminalMatch,
               rule.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(
                    ClashRuleValidationIssue(
                        message: "第 \(index + 1) 条 \(rule.type) 缺少匹配内容。",
                        isError: true,
                        ruleID: rule.id
                    )
                )
            }
            if !availableTargets.isEmpty, !targets.contains(rule.target) {
                issues.append(
                    ClashRuleValidationIssue(
                        message: "第 \(index + 1) 条规则引用了不存在的出口或节点“\(rule.target)”。",
                        isError: true,
                        ruleID: rule.id
                    )
                )
            }
            if rule.isTerminalMatch {
                if sawMatchIndex != nil {
                    issues.append(
                        ClashRuleValidationIssue(
                            message: "存在多条 MATCH；只有最后一条会生效。",
                            isError: true,
                            ruleID: rule.id
                        )
                    )
                }
                sawMatchIndex = index
            } else if sawMatchIndex != nil {
                issues.append(
                    ClashRuleValidationIssue(
                        message: "第 \(index + 1) 条位于 MATCH 之后，永远不会命中。",
                        isError: true,
                        ruleID: rule.id
                    )
                )
            }
            let key = rule.text.lowercased()
            if !seen.insert(key).inserted {
                issues.append(
                    ClashRuleValidationIssue(
                        message: "第 \(index + 1) 条规则与前面的规则重复。",
                        isError: false,
                        ruleID: rule.id
                    )
                )
            }
        }

        if sawMatchIndex == nil {
            issues.append(
                ClashRuleValidationIssue(
                    message: "没有最终 MATCH；未命中的流量将依赖 mihomo 的默认行为。",
                    isError: false
                )
            )
        } else if sawMatchIndex != rules.count - 1 {
            issues.append(
                ClashRuleValidationIssue(
                    message: "MATCH 不在规则列表末尾，请调整顺序。",
                    isError: true
                )
            )
        }

        let text = try replaceRules(
            in: document.originalText,
            rules: rules
        )

        if let before = try? ConfigScanner.analyze(text: document.originalText),
           let after = try? ConfigScanner.analyze(text: text) {
            let beforeCritical = before.findings.filter {
                $0.category == .configError && $0.severity == .critical
            }.count
            let afterCritical = after.findings.filter {
                $0.category == .configError && $0.severity == .critical
            }.count
            if afterCritical > beforeCritical {
                issues.append(
                    ClashRuleValidationIssue(
                        message: "规则改写新增了 \(afterCritical - beforeCritical) 项严重配置错误。",
                        isError: true
                    )
                )
            }
        }

        return ClashRuleValidation(text: text, issues: issues)
    }

    public func apply(
        document: ClashRuleDocument,
        renderedText: String,
        socket: URL?
    ) async throws -> ClashRuleApplyReport {
        let current = try String(
            contentsOf: document.activeConfig,
            encoding: .utf8
        )
        guard current == document.originalText else {
            throw ConfigParseError.unreadable(
                "活动配置在编辑期间发生了变化，请重新载入规则后再应用。"
            )
        }
        guard renderedText != current else {
            return ClashRuleApplyReport(
                changed: false,
                backup: nil,
                reloadSucceeded: socket != nil,
                reloadMessage: socket == nil
                    ? "规则没有变化，且未找到控制接口。"
                    : "规则没有变化，无需重载。"
            )
        }

        let backup = try makeBackup(document.activeConfig)
        try Data(renderedText.utf8).write(
            to: document.activeConfig,
            options: .atomic
        )

        guard let socket else {
            return ClashRuleApplyReport(
                changed: true,
                backup: backup,
                reloadSucceeded: false,
                reloadMessage: "完整 YAML 已写入，但未找到控制接口；请重新加载配置。"
            )
        }
        let reload = await ClashVergeService().reloadActiveConfig(
            socket: socket,
            payload: renderedText
        )
        return ClashRuleApplyReport(
            changed: true,
            backup: backup,
            reloadSucceeded: reload.0,
            reloadMessage: reload.1
        )
    }

    private func replaceRules(
        in text: String,
        rules: [EditableClashRule]
    ) throws -> String {
        let source = try YAMLSource(text: text)
        var lines = source.lines
        let lineEnding = source.lineEnding
        let headerIndex: Int
        let bodyStart: Int
        let bodyEnd: Int

        if let section = source.section(named: "rules") {
            headerIndex = section.lowerBound - 1
            bodyStart = section.lowerBound
            var end = section.upperBound
            while end > bodyStart, source.line(end - 1).isIgnorable {
                end -= 1
            }
            bodyEnd = end
        } else {
            headerIndex = lines.count
            bodyStart = lines.count
            bodyEnd = lines.count
        }

        let indent: Int
        if let section = source.section(named: "rules"),
           let firstRule = section.first(where: {
               source.line($0).startsSequenceItem
           }) {
            indent = source.line(firstRule).indent
        } else {
            indent = 2
        }
        let pad = String(repeating: " ", count: indent)
        let rendered = rules.map {
            "\(pad)- \(yamlQuote($0.text))"
        }

        if bodyStart < lines.count {
            let header = source.line(headerIndex)
            lines[headerIndex] = String(
                repeating: " ",
                count: header.indent
            ) + "rules:"
            lines.replaceSubrange(bodyStart..<bodyEnd, with: rendered)
        } else {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("rules:")
            lines.append(contentsOf: rendered)
        }
        return lines.joined(separator: lineEnding)
    }

    private func yamlQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func makeBackup(_ source: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = directory.appendingPathComponent(
            "\(base).dnsleakguard-backup.\(formatter.string(from: Date())).\(ext)"
        )
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent(
                "\(base).dnsleakguard-backup.\(formatter.string(from: Date()))-\(suffix).\(ext)"
            )
            suffix += 1
        }
        try FileManager.default.copyItem(at: source, to: candidate)
        return candidate
    }
}
