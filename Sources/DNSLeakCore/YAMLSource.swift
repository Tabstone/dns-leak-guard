import Foundation

enum ConfigParseError: LocalizedError {
    case empty
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            "配置文件为空。"
        case let .unreadable(message):
            "无法解析配置：\(message)"
        }
    }
}

struct ScalarToken {
    let value: String
    let start: Int
    let end: Int
    let quote: Character?
}

struct YAMLLine {
    let index: Int
    let raw: String
    let indent: Int
    let content: String
    let isIgnorable: Bool

    var startsSequenceItem: Bool {
        content == "-" || content.hasPrefix("- ")
    }

    var isTopLevelKey: Bool {
        indent == 0 && !isIgnorable && !startsSequenceItem
    }
}

struct YAMLSource {
    let text: String
    let lineEnding: String
    let lines: [String]
    let yamlLines: [YAMLLine]

    init(text: String) throws {
        guard !text.isEmpty else { throw ConfigParseError.empty }
        self.text = text
        self.lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        self.lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                if line.last == "\r" {
                    return String(line.dropLast())
                }
                return String(line)
            }

        var parsed: [YAMLLine] = []
        parsed.reserveCapacity(lines.count)
        for (index, raw) in lines.enumerated() {
            var indent = 0
            for character in raw {
                if character == " " {
                    indent += 1
                } else if character == "\t" {
                    throw ConfigParseError.unreadable("第 \(index + 1) 行使用了 Tab 缩进")
                } else {
                    break
                }
            }
            let content = String(raw.dropFirst(indent))
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            let ignorable = trimmed.isEmpty
                || trimmed.hasPrefix("#")
                || trimmed == "---"
                || trimmed == "..."
            parsed.append(
                YAMLLine(
                    index: index,
                    raw: raw,
                    indent: indent,
                    content: content,
                    isIgnorable: ignorable
                )
            )
        }
        self.yamlLines = parsed
    }

    func section(named name: String) -> Range<Int>? {
        guard let start = yamlLines.firstIndex(where: {
            $0.isTopLevelKey && Self.topLevelKey($0.content) == name
        }) else {
            return nil
        }
        var end = lines.count
        if start + 1 < yamlLines.count {
            for index in (start + 1)..<yamlLines.count where yamlLines[index].isTopLevelKey {
                end = index
                break
            }
        }
        return (start + 1)..<end
    }

    func bodyIndent(in range: Range<Int>) -> Int? {
        for index in range where !yamlLines[index].isIgnorable {
            return yamlLines[index].indent
        }
        return nil
    }

    func line(_ index: Int) -> YAMLLine {
        yamlLines[index]
    }

    static func topLevelKey(_ content: String) -> String? {
        guard let split = splitKeyValue(content) else { return nil }
        return unquote(split.key.trimmingCharacters(in: .whitespaces))
    }

    static func splitKeyValue(_ content: String) -> (key: String, value: String)? {
        var singleQuoted = false
        var doubleQuoted = false
        var escaped = false
        let characters = Array(content)

        for index in characters.indices {
            let character = characters[index]
            if escaped {
                escaped = false
                continue
            }
            if doubleQuoted && character == "\\" {
                escaped = true
                continue
            }
            if character == "'" && !doubleQuoted {
                singleQuoted.toggle()
                continue
            }
            if character == "\"" && !singleQuoted {
                doubleQuoted.toggle()
                continue
            }
            guard character == ":", !singleQuoted, !doubleQuoted else { continue }
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            guard next == " " || next == "\t" || index == characters.count - 1 else { continue }
            let key = String(characters[..<index])
            let valueStart = min(index + 1, characters.count)
            let value = String(characters[valueStart...]).trimmingCharacters(in: .whitespaces)
            return (key, value)
        }
        return nil
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.first == "'", value.last == "'" {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        }
        if value.first == "\"", value.last == "\"" {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return value
    }

    static func boolean(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased() {
        case "true", "yes", "on", "1":
            return true
        case "false", "no", "off", "0":
            return false
        default:
            return nil
        }
    }

    func token(from lineIndex: Int, startingAt start: Int) -> ScalarToken? {
        let raw = lines[lineIndex]
        let ns = raw as NSString
        guard start >= 0, start < ns.length else { return nil }

        var cursor = start
        while cursor < ns.length {
            let scalar = ns.substring(with: NSRange(location: cursor, length: 1))
            if scalar == " " || scalar == "\t" {
                cursor += 1
            } else {
                break
            }
        }
        guard cursor < ns.length else { return nil }

        let first = ns.substring(with: NSRange(location: cursor, length: 1))
        if first == "#" {
            return nil
        }

        if first == "'" || first == "\"" {
            let quote = Character(first)
            let tokenStart = cursor
            cursor += 1
            var escaped = false
            while cursor < ns.length {
                let scalar = ns.substring(with: NSRange(location: cursor, length: 1))
                if quote == "\"" && escaped {
                    escaped = false
                    cursor += 1
                    continue
                }
                if quote == "\"" && scalar == "\\" {
                    escaped = true
                    cursor += 1
                    continue
                }
                if quote == "'" && scalar == "'" {
                    let nextLocation = cursor + 1
                    if nextLocation < ns.length,
                       ns.substring(with: NSRange(location: nextLocation, length: 1)) == "'" {
                        cursor += 2
                        continue
                    }
                }
                if Character(scalar) == quote {
                    cursor += 1
                    break
                }
                cursor += 1
            }
            let rawToken = ns.substring(with: NSRange(location: tokenStart, length: cursor - tokenStart))
            return ScalarToken(
                value: YAMLSource.unquote(rawToken),
                start: tokenStart,
                end: cursor,
                quote: quote
            )
        }

        let tokenStart = cursor
        var previousWasWhitespace = true
        while cursor < ns.length {
            let scalar = ns.substring(with: NSRange(location: cursor, length: 1))
            if scalar == "#" && previousWasWhitespace {
                break
            }
            previousWasWhitespace = scalar == " " || scalar == "\t"
            cursor += 1
        }
        var end = cursor
        while end > tokenStart {
            let scalar = ns.substring(with: NSRange(location: end - 1, length: 1))
            if scalar == " " || scalar == "\t" {
                end -= 1
            } else {
                break
            }
        }
        let rawToken = ns.substring(with: NSRange(location: tokenStart, length: end - tokenStart))
        return ScalarToken(value: rawToken, start: tokenStart, end: end, quote: nil)
    }

    func parseScalarValue(keyLineIndex: Int) -> String? {
        let yaml = yamlLines[keyLineIndex]
        guard let split = YAMLSource.splitKeyValue(yaml.content) else { return nil }
        let trimmed = split.value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "{}", trimmed != "[]" else { return nil }
        return YAMLSource.unquote(trimmed)
    }

    func parseList(keyLineIndex: Int, sectionRange: Range<Int>) -> [DNSServerEntry] {
        let keyLine = yamlLines[keyLineIndex]
        guard let split = YAMLSource.splitKeyValue(keyLine.content) else { return [] }
        let value = split.value.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("[") {
            return parseFlowList(keyLineIndex: keyLineIndex, value: value)
        }
        guard value.isEmpty else { return [] }

        var entries: [DNSServerEntry] = []
        var index = keyLineIndex + 1
        while index < sectionRange.upperBound && index < yamlLines.count {
            let line = yamlLines[index]
            if line.isIgnorable {
                index += 1
                continue
            }
            if line.indent < keyLine.indent {
                break
            }
            if line.indent == keyLine.indent && !line.startsSequenceItem {
                break
            }
            guard line.startsSequenceItem else { break }
            let tokenStart = line.indent + 1
            if let token = token(from: index, startingAt: tokenStart) {
                entries.append(
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
                )
            }
            index += 1
        }
        return entries
    }

    func parseStringList(keyLineIndex: Int, sectionRange: Range<Int>) -> [ScalarToken] {
        let keyLine = yamlLines[keyLineIndex]
        guard let split = YAMLSource.splitKeyValue(keyLine.content) else { return [] }
        let value = split.value.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("[") {
            return parseFlowList(keyLineIndex: keyLineIndex, value: value).map {
                ScalarToken(value: $0.raw, start: $0.tokenStart, end: $0.tokenEnd, quote: $0.quote)
            }
        }
        guard value.isEmpty else {
            let token = token(from: keyLineIndex, startingAt: keyLine.indent + keyLine.content.count - value.count)
            return token.map { [$0] } ?? []
        }

        var result: [ScalarToken] = []
        var index = keyLineIndex + 1
        while index < sectionRange.upperBound && index < yamlLines.count {
            let line = yamlLines[index]
            if line.isIgnorable {
                index += 1
                continue
            }
            if line.indent < keyLine.indent {
                break
            }
            if line.indent == keyLine.indent && !line.startsSequenceItem {
                break
            }
            guard line.startsSequenceItem else { break }
            if let token = token(from: index, startingAt: line.indent + 1) {
                result.append(token)
            }
            index += 1
        }
        return result
    }

    private func parseFlowList(keyLineIndex: Int, value: String) -> [DNSServerEntry] {
        guard value.hasPrefix("[") else { return [] }
        let line = yamlLines[keyLineIndex]
        let contentStart = line.indent + line.content.count - value.count
        let rawLine = lines[keyLineIndex] as NSString
        var open = contentStart
        while open < rawLine.length,
              rawLine.substring(with: NSRange(location: open, length: 1)) != "[" {
            open += 1
        }
        var close = rawLine.length - 1
        while close > open,
              rawLine.substring(with: NSRange(location: close, length: 1)) != "]" {
            close -= 1
        }
        guard open < close else { return [] }

        let inner = NSRange(location: open + 1, length: close - open - 1)
        let innerText = rawLine.substring(with: inner) as NSString
        var ranges: [NSRange] = []
        var start = 0
        var quote: Character?
        var escaped = false
        for index in 0..<innerText.length {
            let scalar = innerText.substring(with: NSRange(location: index, length: 1))
            if escaped {
                escaped = false
                continue
            }
            if quote == "\"" && scalar == "\\" {
                escaped = true
                continue
            }
            if scalar == "'" || scalar == "\"" {
                if quote == nil {
                    quote = Character(scalar)
                } else if Character(scalar) == quote {
                    quote = nil
                }
                continue
            }
            if scalar == ",", quote == nil {
                ranges.append(NSRange(location: start, length: index - start))
                start = index + 1
            }
        }
        ranges.append(NSRange(location: start, length: innerText.length - start))

        return ranges.compactMap { range in
            var localStart = range.location
            var localEnd = range.location + range.length
            while localStart < localEnd,
                  innerText.substring(with: NSRange(location: localStart, length: 1))
                    .trimmingCharacters(in: .whitespaces).isEmpty {
                localStart += 1
            }
            while localEnd > localStart,
                  innerText.substring(with: NSRange(location: localEnd - 1, length: 1))
                    .trimmingCharacters(in: .whitespaces).isEmpty {
                localEnd -= 1
            }
            guard localStart < localEnd else { return nil }
            let absoluteStart = open + 1 + localStart
            let absoluteEnd = open + 1 + localEnd
            let rawToken = rawLine.substring(
                with: NSRange(location: absoluteStart, length: absoluteEnd - absoluteStart)
            )
            let first = rawToken.first
            let quote = (first == "'" || first == "\"") ? first : nil
            return DNSServerEntry(
                raw: YAMLSource.unquote(rawToken),
                list: nil,
                line: keyLineIndex,
                tokenStart: absoluteStart,
                tokenEnd: absoluteEnd,
                quote: quote,
                policyKey: nil,
                policySubkey: nil
            )
        }
    }
}
