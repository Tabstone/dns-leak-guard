import CryptoKit
import Foundation

public struct DNSOverrideContext: Sendable {
    public let profileUID: String
    public let profileFile: URL
    public let expectedConfirmation: String?

    public init(profileUID: String, profileFile: URL, expectedConfirmation: String?) {
        self.profileUID = profileUID
        self.profileFile = profileFile
        self.expectedConfirmation = expectedConfirmation
    }
}

public enum DNSOverrideConfirmation {
    private static let providerFields = [
        "proxy-server-nameserver",
        "proxy-server-nameserver-policy",
        "nameserver-policy"
    ]

    public static func source(
        profileUID: String,
        profileText: String
    ) throws -> String? {
        guard !profileUID.isEmpty else { return nil }
        let source = try YAMLSource(text: profileText)
        guard let dnsLine = source.yamlLines.first(where: {
            $0.isTopLevelKey && YAMLSource.topLevelKey($0.content) == "dns"
        }),
        let split = YAMLSource.splitKeyValue(dnsLine.content) else {
            return nil
        }

        let dns: YAMLValue
        let inlineValue = split.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inlineValue.isEmpty {
            guard inlineValue.hasPrefix("{") else { return nil }
            var parser = FlowValueParser(inlineValue)
            dns = try parser.parse()
        } else {
            guard let section = source.section(named: "dns"),
                  let bodyIndent = source.bodyIndent(in: section) else {
                return nil
            }
            let parser = YAMLNodeParser(
                source: source,
                limit: section.upperBound
            )
            var fields: [String: YAMLValue] = [:]
            for field in providerFields {
                guard let index = section.first(where: { index in
                    let line = source.line(index)
                    guard !line.isIgnorable,
                          line.indent == bodyIndent,
                          !line.startsSequenceItem,
                          let split = YAMLSource.splitKeyValue(line.content) else {
                        return false
                    }
                    return YAMLSource.unquote(
                        split.key.trimmingCharacters(in: .whitespaces)
                    ) == field
                }) else {
                    continue
                }
                let (value, _) = try parser.parseEntry(at: index)
                if value.isNonEmptyProviderValue {
                    fields[field] = value
                }
            }
            dns = .object(fields)
        }

        guard case let .object(dnsObject) = dns else { return nil }
        let fields = dnsObject.filter { _, value in
            value.isNonEmptyProviderValue
        }
        guard !fields.isEmpty else { return nil }

        let canonical = YAMLValue.object(fields).canonicalJSON
        var input = Data(profileUID.utf8)
        input.append(0)
        input.append(Data(canonical.utf8))
        return SHA256.hash(data: input)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private enum YAMLValue {
    case string(String)
    case array([YAMLValue])
    case object([String: YAMLValue])
    case null

    var isNonEmptyProviderValue: Bool {
        switch self {
        case let .string(value):
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .array(values):
            return !values.isEmpty
        case let .object(values):
            return !values.isEmpty
        case .null:
            return false
        }
    }

    var canonicalJSON: String {
        switch self {
        case let .string(value):
            return Self.jsonString(value)
        case let .array(values):
            return "[" + values.map(\.canonicalJSON).joined(separator: ",") + "]"
        case let .object(values):
            let sortedKeys = values.keys.sorted {
                Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8))
            }
            let body = sortedKeys.compactMap { key -> String? in
                guard let value = values[key] else { return nil }
                return Self.jsonString(key) + ":" + value.canonicalJSON
            }
            return "{" + body.joined(separator: ",") + "}"
        case .null:
            return "null"
        }
    }

    private static func jsonString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                result += "\\\""
            case 0x5C:
                result += "\\\\"
            case 0x08:
                result += "\\b"
            case 0x0C:
                result += "\\f"
            case 0x0A:
                result += "\\n"
            case 0x0D:
                result += "\\r"
            case 0x09:
                result += "\\t"
            case 0x00..<0x20:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }
}

private struct YAMLNodeParser {
    let source: YAMLSource
    let limit: Int

    func parseEntry(at index: Int) throws -> (YAMLValue, Int) {
        let line = source.line(index)
        guard let split = YAMLSource.splitKeyValue(line.content) else {
            return (.null, index + 1)
        }
        let rawValue = split.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawValue.isEmpty {
            let (text, next) = inlineValue(
                startingAt: index,
                initial: rawValue
            )
            if text.hasPrefix("[") || text.hasPrefix("{") {
                var parser = FlowValueParser(text)
                return (try parser.parse(), next)
            }
            return (Self.scalar(text), index + 1)
        }

        var cursor = index + 1
        while cursor < limit && source.line(cursor).isIgnorable {
            cursor += 1
        }
        guard cursor < limit, source.line(cursor).indent > line.indent else {
            return (.null, index + 1)
        }
        return try parseBlockValue(startingAt: cursor)
    }

    private func parseBlockValue(
        startingAt start: Int
    ) throws -> (YAMLValue, Int) {
        let first = source.line(start)
        if first.startsSequenceItem {
            return try parseSequence(indent: first.indent, startingAt: start)
        }
        return try parseMapping(indent: first.indent, startingAt: start)
    }

    private func parseMapping(
        indent: Int,
        startingAt start: Int
    ) throws -> (YAMLValue, Int) {
        var object: [String: YAMLValue] = [:]
        var index = start
        while index < limit {
            let line = source.line(index)
            if line.isIgnorable {
                index += 1
                continue
            }
            if line.indent < indent || line.startsSequenceItem {
                break
            }
            guard line.indent == indent,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                index += 1
                continue
            }
            let key = YAMLSource.unquote(
                split.key.trimmingCharacters(in: .whitespaces)
            )
            let (value, next) = try parseEntry(at: index)
            object[key] = value
            index = max(next, index + 1)
        }
        return (.object(object), index)
    }

    private func parseSequence(
        indent: Int,
        startingAt start: Int
    ) throws -> (YAMLValue, Int) {
        var values: [YAMLValue] = []
        var index = start
        while index < limit {
            let line = source.line(index)
            if line.isIgnorable {
                index += 1
                continue
            }
            guard line.indent == indent, line.startsSequenceItem else {
                break
            }
            let content = String(line.content.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                var cursor = index + 1
                while cursor < limit && source.line(cursor).isIgnorable {
                    cursor += 1
                }
                guard cursor < limit, source.line(cursor).indent > indent else {
                    values.append(.null)
                    index += 1
                    continue
                }
                let (value, next) = try parseBlockValue(startingAt: cursor)
                values.append(value)
                index = max(next, index + 1)
                continue
            }
            let (text, next) = inlineValue(
                startingAt: index,
                initial: content
            )
            if text.hasPrefix("[") || text.hasPrefix("{") {
                var parser = FlowValueParser(text)
                values.append(try parser.parse())
            } else {
                values.append(Self.scalar(text))
            }
            index = max(next, index + 1)
        }
        return (.array(values), index)
    }

    private func inlineValue(
        startingAt index: Int,
        initial: String
    ) -> (String, Int) {
        var text = Self.stripComment(initial)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("[") || text.hasPrefix("{") else {
            return (text, index + 1)
        }

        var cursor = index + 1
        var depth = Self.bracketDepth(text)
        while depth > 0, cursor < limit {
            let line = source.line(cursor)
            if !line.isIgnorable {
                text += " " + Self.stripComment(line.content)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                depth = Self.bracketDepth(text)
            }
            cursor += 1
        }
        return (text, cursor)
    }

    private static func scalar(_ raw: String) -> YAMLValue {
        let value = stripComment(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "~" || value.lowercased() == "null" {
            return .null
        }
        if value == "[]" {
            return .array([])
        }
        if value == "{}" {
            return .object([:])
        }
        return .string(YAMLSource.unquote(value))
    }

    private static func stripComment(_ value: String) -> String {
        var quote: Character?
        var escaped = false
        var previousWasWhitespace = true
        var result = ""
        for character in value {
            if escaped {
                result.append(character)
                escaped = false
                previousWasWhitespace = character.isWhitespace
                continue
            }
            if quote == "\"" && character == "\\" {
                result.append(character)
                escaped = true
                continue
            }
            if character == "'" || character == "\"" {
                if quote == nil {
                    quote = character
                } else if quote == character {
                    quote = nil
                }
                result.append(character)
                previousWasWhitespace = false
                continue
            }
            if character == "#", quote == nil, previousWasWhitespace {
                break
            }
            result.append(character)
            previousWasWhitespace = character.isWhitespace
        }
        return result
    }

    private static func bracketDepth(_ text: String) -> Int {
        var depth = 0
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped {
                escaped = false
                continue
            }
            if quote == "\"" && character == "\\" {
                escaped = true
                continue
            }
            if character == "'" || character == "\"" {
                if quote == nil {
                    quote = character
                } else if quote == character {
                    quote = nil
                }
                continue
            }
            guard quote == nil else { continue }
            if character == "[" || character == "{" {
                depth += 1
            } else if character == "]" || character == "}" {
                depth -= 1
            }
        }
        return max(0, depth)
    }
}

private struct FlowValueParser {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        self.characters = Array(text)
    }

    mutating func parse() throws -> YAMLValue {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == characters.count else {
            throw ConfigParseError.unreadable("DNS 覆写字段包含无法解析的 YAML 流式值")
        }
        return value
    }

    private mutating func parseValue() throws -> YAMLValue {
        skipWhitespace()
        guard index < characters.count else { return .null }
        switch characters[index] {
        case "{":
            return try parseObject()
        case "[":
            return try parseArray()
        case "'", "\"":
            return .string(try parseQuoted())
        default:
            let value = parsePlain(until: [",", "]", "}"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || value == "~" || value.lowercased() == "null" {
                return .null
            }
            return .string(YAMLSource.unquote(value))
        }
    }

    private mutating func parseObject() throws -> YAMLValue {
        index += 1
        var object: [String: YAMLValue] = [:]
        skipWhitespace()
        if consume("}") {
            return .object(object)
        }
        while index < characters.count {
            skipWhitespace()
            let key: String
            if index < characters.count,
               characters[index] == "'" || characters[index] == "\"" {
                key = try parseQuoted()
            } else {
                key = parsePlain(until: [":"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            skipWhitespace()
            guard consume(":") else {
                throw ConfigParseError.unreadable("DNS 覆写字段的 YAML 映射缺少冒号")
            }
            let value = try parseValue()
            object[YAMLSource.unquote(key)] = value
            skipWhitespace()
            if consume("}") {
                return .object(object)
            }
            guard consume(",") else {
                throw ConfigParseError.unreadable("DNS 覆写字段的 YAML 映射缺少逗号")
            }
        }
        throw ConfigParseError.unreadable("DNS 覆写字段的 YAML 映射未闭合")
    }

    private mutating func parseArray() throws -> YAMLValue {
        index += 1
        var values: [YAMLValue] = []
        skipWhitespace()
        if consume("]") {
            return .array(values)
        }
        while index < characters.count {
            values.append(try parseValue())
            skipWhitespace()
            if consume("]") {
                return .array(values)
            }
            guard consume(",") else {
                throw ConfigParseError.unreadable("DNS 覆写字段的 YAML 列表缺少逗号")
            }
        }
        throw ConfigParseError.unreadable("DNS 覆写字段的 YAML 列表未闭合")
    }

    private mutating func parseQuoted() throws -> String {
        guard index < characters.count else { return "" }
        let quote = characters[index]
        index += 1
        var result = ""
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            index += 1
            if escaped {
                switch character {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default: result.append(character)
                }
                escaped = false
                continue
            }
            if quote == "\"", character == "\\" {
                escaped = true
                continue
            }
            if character == quote {
                if quote == "'",
                   index < characters.count,
                   characters[index] == "'" {
                    result.append("'")
                    index += 1
                    continue
                }
                return result
            }
            result.append(character)
        }
        throw ConfigParseError.unreadable("DNS 覆写字段包含未闭合的引号")
    }

    private mutating func parsePlain(until delimiters: Set<Character>) -> String {
        var result = ""
        while index < characters.count {
            let character = characters[index]
            if delimiters.contains(character) {
                break
            }
            result.append(character)
            index += 1
        }
        return result
    }

    private mutating func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard index < characters.count, characters[index] == character else {
            return false
        }
        index += 1
        return true
    }
}
