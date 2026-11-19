import Foundation

public final class ClashVergeService {
    public init() {}

    public func discover() async -> WorkspaceInfo? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(
                "Library/Application Support/io.github.clash-verge-rev.clash-verge-rev",
                isDirectory: true
            ),
            home.appendingPathComponent(
                "Library/Application Support/clash-verge",
                isDirectory: true
            )
        ]
        guard let directory = candidates.first(where: {
            fileManager.fileExists(atPath: $0.appendingPathComponent("clash-verge.yaml").path)
        }) else {
            return nil
        }

        let active = directory.appendingPathComponent("clash-verge.yaml")
        let dnsOverride = existing(
            directory.appendingPathComponent("dns_config.yaml"),
            fileManager: fileManager
        )
        let verge = existing(
            directory.appendingPathComponent("verge.yaml"),
            fileManager: fileManager
        )
        let profiles = existing(
            directory.appendingPathComponent("profiles.yaml"),
            fileManager: fileManager
        )

        var socketCandidates: [URL] = [
            URL(fileURLWithPath: "/var/run/clash-verge-service/users/\(getuid())/verge-mihomo.sock"),
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("verge-mihomo.sock"),
            fileManager.temporaryDirectory.appendingPathComponent("verge-mihomo.sock")
        ]
        if let configured = configuredSocket(from: active) {
            socketCandidates.insert(configured, at: 0)
        }

        var workingSocket: URL?
        for candidate in socketCandidates where fileManager.fileExists(atPath: candidate.path) {
            if let _ = try? await UnixHTTPClient.get(
                socketPath: candidate.path,
                path: "/version"
            ) {
                workingSocket = candidate
                break
            }
        }

        return WorkspaceInfo(
            directory: directory,
            activeConfig: active,
            dnsOverride: dnsOverride,
            vergeSettings: verge,
            profilesFile: profiles,
            controlSocket: workingSocket,
            isClashVergeRunning: workingSocket != nil
        )
    }

    public func analyze(workspace: WorkspaceInfo) throws -> ConfigAnalysis {
        let data = try Data(contentsOf: workspace.activeConfig)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigParseError.unreadable("活动配置不是 UTF-8 文本")
        }
        return try ConfigScanner.analyze(text: text)
    }

    public func dnsOverrideContext(
        workspace: WorkspaceInfo
    ) throws -> DNSOverrideContext? {
        guard let profilesURL = workspace.profilesFile else { return nil }
        let profilesText = try String(contentsOf: profilesURL, encoding: .utf8)
        let profiles = try YAMLSource(text: profilesText)
        guard let currentLine = profiles.yamlLines.first(where: {
            $0.isTopLevelKey && YAMLSource.topLevelKey($0.content) == "current"
        }),
        let currentSplit = YAMLSource.splitKeyValue(currentLine.content) else {
            return nil
        }
        let profileUID = YAMLSource.unquote(
            currentSplit.value.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !profileUID.isEmpty else { return nil }

        let fileName = profileFileName(
            profileUID: profileUID,
            profiles: profiles
        )
        let profilesDirectory = workspace.directory
            .appendingPathComponent("profiles", isDirectory: true)
        let candidates = [
            fileName.map { profilesDirectory.appendingPathComponent($0) },
            profilesDirectory.appendingPathComponent("\(profileUID).yaml"),
            profilesDirectory.appendingPathComponent("\(profileUID).yml")
        ].compactMap { $0 }

        let normalizedDirectory = profilesDirectory.standardizedFileURL.path + "/"
        guard let profileFile = candidates.first(where: {
            let path = $0.standardizedFileURL.path
            return path.hasPrefix(normalizedDirectory)
                && FileManager.default.fileExists(atPath: path)
        }) else {
            throw ConfigParseError.unreadable(
                "找不到当前订阅的原始配置文件，无法计算 Clash Verge DNS 覆写确认值。"
            )
        }

        let profileText = try String(contentsOf: profileFile, encoding: .utf8)
        let confirmation = try DNSOverrideConfirmation.source(
            profileUID: profileUID,
            profileText: profileText
        )
        return DNSOverrideContext(
            profileUID: profileUID,
            profileFile: profileFile,
            expectedConfirmation: confirmation
        )
    }

    public func runtimeStatus(workspace: WorkspaceInfo) async -> ClashRuntimeStatus? {
        guard let socket = workspace.controlSocket else { return nil }
        guard let response = try? await UnixHTTPClient.get(
            socketPath: socket.path,
            path: "/configs"
        ),
        let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            return nil
        }
        let globalSelection: String?
        if let proxyResponse = try? await UnixHTTPClient.get(
            socketPath: socket.path,
            path: "/proxies/GLOBAL"
        ),
        let proxyObject = try? JSONSerialization.jsonObject(
            with: proxyResponse.body
        ) as? [String: Any] {
            globalSelection = proxyObject["now"] as? String
        } else {
            globalSelection = nil
        }
        return ClashRuntimeStatus(
            mode: object["mode"] as? String,
            tunEnabled: (object["tun"] as? [String: Any])?["enable"] as? Bool,
            mixedPort: object["mixed-port"] as? Int,
            globalSelection: globalSelection
        )
    }

    public func health(workspace: WorkspaceInfo) -> WorkspaceHealth {
        var warnings: [String] = []
        let overrideState = profileDNSOverrideState(workspace: workspace)
        if overrideState == false {
            warnings.append("当前订阅的 Clash Verge DNS 覆写未启用或确认值已失效，dns_config.yaml 可能不会生效。")
        } else if overrideState == nil {
            warnings.append("未能确认当前订阅的 DNS 覆写开关，请在 Clash Verge 中检查。")
        }

        if let context = try? dnsOverrideContext(workspace: workspace),
           let settings = profileDNSOverrideSettings(workspace: workspace),
           settings.enabled == true,
           let expected = context.expectedConfirmation,
           settings.confirmation != expected {
            warnings.append("Clash Verge DNS 覆写的 confirmation 与当前订阅 DNS 字段不一致；应用修复时会自动重新确认。")
        }

        if let dnsOverride = workspace.dnsOverride,
           let active = try? String(contentsOf: workspace.activeConfig, encoding: .utf8),
           let override = try? String(contentsOf: dnsOverride, encoding: .utf8) {
            let activeParsed = try? ConfigParser.parse(text: active)
            let overrideParsed = try? ConfigParser.parse(text: override)
            if overrideParsed?.dns?.ipv6 == false, activeParsed?.dns?.ipv6 == true {
                warnings.append(
                    "Clash Verge 的布尔合并缺陷会把 dns.ipv6: false 当作“未填写”；当前活动配置仍继承了 ipv6: true。需要脚本或扩展配置才能可靠关闭。"
                )
            }
        }
        warnings.append("规则类修复只写入当前生成配置；订阅刷新后可能被上游覆盖，DNS 覆写项会保留。")
        return WorkspaceHealth(
            profileDNSOverrideEnabled: overrideState,
            warnings: warnings
        )
    }

    public func preview(
        workspace: WorkspaceInfo,
        selection: FixSelection,
        proxyGroup: String?
    ) throws -> ConfigFixer.Result {
        let text = try String(contentsOf: workspace.activeConfig, encoding: .utf8)
        return try ConfigFixer.preview(
            text: text,
            selection: selection,
            proxyGroup: proxyGroup,
            includeRuleFixes: true
        )
    }

    public func apply(
        workspace: WorkspaceInfo,
        selection: FixSelection,
        proxyGroup: String?,
        persistDNSOverride: Bool
    ) async throws -> FixApplicationReport {
        let activeText = try String(contentsOf: workspace.activeConfig, encoding: .utf8)
        let overrideContext = persistDNSOverride
            ? try dnsOverrideContext(workspace: workspace)
            : nil
        let activeResult = try ConfigFixer.apply(
            text: activeText,
            selection: selection,
            proxyGroup: proxyGroup,
            includeRuleFixes: true
        )

        if activeResult.text != activeText {
            let verification = try ConfigScanner.analyze(text: activeResult.text)
            let before = try ConfigScanner.analyze(text: activeText)
            let newErrors = verification.findings.filter {
                $0.category == .configError && $0.severity == .critical
            }.count
            let oldErrors = before.findings.filter {
                $0.category == .configError && $0.severity == .critical
            }.count
            guard newErrors <= oldErrors else {
                throw ConfigParseError.unreadable("修复后的配置新增了严重错误，已取消写入")
            }
        }

        var pendingWrites: [(url: URL, data: Data)] = []
        var mergedActions = activeResult.appliedActions
        var mergedNotes = activeResult.notes
        var totalChanges = activeResult.changeCount

        if activeResult.text != activeText {
            pendingWrites.append((workspace.activeConfig, Data(activeResult.text.utf8)))
        }

        if persistDNSOverride, let overrideURL = workspace.dnsOverride {
            let original = try String(contentsOf: overrideURL, encoding: .utf8)
            let result = try ConfigFixer.apply(
                text: original,
                selection: selection,
                proxyGroup: proxyGroup,
                includeRuleFixes: false
            )
            if result.text != original {
                let verification = try ConfigScanner.analyze(text: result.text)
                if verification.findings.contains(where: {
                    $0.category == .configError && $0.code.hasPrefix("DNS-0")
                }) {
                    mergedNotes.append("DNS 覆写文件复检仍有配置错误，请查看扫描结果。")
                }
                pendingWrites.append((overrideURL, Data(result.text.utf8)))
                totalChanges += result.changeCount
                mergedActions.append(contentsOf: result.appliedActions)
                mergedNotes.append(contentsOf: result.notes)
            }
        }

        if persistDNSOverride,
           let vergeURL = workspace.vergeSettings,
           workspace.profilesFile != nil {
            guard let overrideContext else {
                throw ConfigParseError.unreadable(
                    "无法确定当前订阅的 DNS 覆写来源；为避免 Clash Verge 自动关闭覆写，已取消写入。"
                )
            }
            let update = try enableProfileDNSOverride(
                vergeURL: vergeURL,
                profileUID: overrideContext.profileUID,
                confirmation: overrideContext.expectedConfirmation
            )
            if update.changed {
                pendingWrites.append((vergeURL, Data(update.text.utf8)))
                totalChanges += update.changes
                mergedNotes.append("已启用当前订阅的 Clash Verge DNS 覆写。")
            }
        }

        let uniqueWrites = deduplicateWrites(pendingWrites)
        let (changedFiles, backups) = try writeWithBackups(uniqueWrites)
        let reload: (Bool, String)
        if let socket = workspace.controlSocket {
            reload = await reloadActiveConfig(
                socket: socket,
                payload: activeResult.text
            )
        } else {
            reload = (
                false,
                changedFiles.isEmpty
                    ? "没有文件需要写入。"
                    : "配置已写入，但未找到运行中的 Clash Verge 控制接口；请重新加载配置。"
            )
        }

        if persistDNSOverride {
            mergedNotes.append("订阅或 Clash Verge 重新生成配置后，规则类修改可能被上游覆盖；DNS 覆写项会保留。")
        }
        if activeResult.appliedActions.contains(.addNoResolve) {
            mergedNotes.append("no-resolve 只写入当前生成配置，刷新订阅后应重新扫描确认。")
        }

        return FixApplicationReport(
            changedFiles: changedFiles,
            backups: backups,
            changeCount: totalChanges,
            appliedActions: FixOptionType.allCases.filter(Set(mergedActions).contains),
            notes: uniqueStrings(mergedNotes),
            reloadSucceeded: reload.0,
            reloadMessage: reload.1
        )
    }

    public func reloadActiveConfig(
        socket: URL,
        payload: String
    ) async -> (Bool, String) {
        do {
            _ = try await UnixHTTPClient.put(
                socketPath: socket.path,
                path: "/configs?force=true",
                jsonBody: ["payload": payload]
            )
            try? await Task.sleep(nanoseconds: 350_000_000)
            return (true, "已通过控制接口提交最新配置并完成重载。")
        } catch {
            return (false, "配置已写入，但重载失败：\(error.localizedDescription)")
        }
    }

    private func configuredSocket(from activeConfig: URL) -> URL? {
        guard let text = try? String(contentsOf: activeConfig, encoding: .utf8) else {
            return nil
        }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("external-controller-unix:") else { continue }
            let value = trimmed
                .replacingOccurrences(of: "external-controller-unix:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty {
                return URL(fileURLWithPath: value)
            }
        }
        return nil
    }

    private func profileFileName(
        profileUID: String,
        profiles: YAMLSource
    ) -> String? {
        guard let section = profiles.section(named: "items") else {
            return nil
        }

        var records: [(uid: String?, file: String?)] = []
        var currentUID: String?
        var currentFile: String?
        var itemIndent: Int?
        for index in section {
            let line = profiles.line(index)
            if line.isIgnorable {
                continue
            }
            if line.startsSequenceItem,
               itemIndent == nil || line.indent == itemIndent {
                if currentUID != nil || currentFile != nil {
                    records.append((currentUID, currentFile))
                }
                currentUID = nil
                currentFile = nil
                itemIndent = line.indent
                let content = String(line.content.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                if let split = YAMLSource.splitKeyValue(content) {
                    let key = YAMLSource.unquote(
                        split.key.trimmingCharacters(in: .whitespaces)
                    )
                    let value = YAMLSource.unquote(
                        split.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    if key == "uid" {
                        currentUID = value
                    } else if key == "file" {
                        currentFile = value
                    }
                }
                continue
            }
            guard let itemIndent,
                  line.indent > itemIndent,
                  !line.startsSequenceItem,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                continue
            }
            let key = YAMLSource.unquote(
                split.key.trimmingCharacters(in: .whitespaces)
            )
            let value = YAMLSource.unquote(
                split.value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if key == "uid" {
                currentUID = value
            } else if key == "file" {
                currentFile = value
            }
        }
        if currentUID != nil || currentFile != nil {
            records.append((currentUID, currentFile))
        }
        return records.first(where: { $0.uid == profileUID })?.file
    }

    private func profileDNSOverrideSettings(
        workspace: WorkspaceInfo
    ) -> (enabled: Bool?, confirmation: String?)? {
        guard let vergeURL = workspace.vergeSettings,
              let profilesURL = workspace.profilesFile,
              let profilesText = try? String(contentsOf: profilesURL, encoding: .utf8),
              let vergeText = try? String(contentsOf: vergeURL, encoding: .utf8),
              let profilesSource = try? YAMLSource(text: profilesText),
              let vergeSource = try? YAMLSource(text: vergeText),
              let currentLine = profilesSource.yamlLines.first(where: {
                  $0.isTopLevelKey && YAMLSource.topLevelKey($0.content) == "current"
              }),
              let currentSplit = YAMLSource.splitKeyValue(currentLine.content) else {
            return nil
        }
        let current = YAMLSource.unquote(
            currentSplit.value.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !current.isEmpty,
              let section = vergeSource.section(named: "profile_dns_settings"),
              let bodyIndent = vergeSource.bodyIndent(in: section) else {
            return nil
        }
        guard let profileLine = section.first(where: { index in
            let line = vergeSource.line(index)
            guard !line.isIgnorable,
                  line.indent == bodyIndent,
                  !line.startsSequenceItem,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                return false
            }
            return YAMLSource.unquote(split.key.trimmingCharacters(in: .whitespaces)) == current
        }) else {
            return nil
        }
        var index = profileLine + 1
        while index < section.upperBound {
            let line = vergeSource.line(index)
            if !line.isIgnorable, line.indent <= bodyIndent { break }
            if !line.isIgnorable,
               !line.startsSequenceItem,
               let split = YAMLSource.splitKeyValue(line.content),
               line.indent == bodyIndent + 2 {
                let key = YAMLSource.unquote(
                    split.key.trimmingCharacters(in: .whitespaces)
                )
                if key == "enabled" {
                    let enabled = YAMLSource.boolean(split.value)
                    var confirmation: String?
                    var scan = index + 1
                    while scan < section.upperBound {
                        let candidate = vergeSource.line(scan)
                        if !candidate.isIgnorable, candidate.indent <= bodyIndent {
                            break
                        }
                        if !candidate.isIgnorable,
                           !candidate.startsSequenceItem,
                           candidate.indent == line.indent,
                           let candidateSplit = YAMLSource.splitKeyValue(
                            candidate.content
                           ),
                           YAMLSource.unquote(
                            candidateSplit.key.trimmingCharacters(in: .whitespaces)
                           ) == "confirmation" {
                            confirmation = YAMLSource.unquote(
                                candidateSplit.value.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            )
                            break
                        }
                        scan += 1
                    }
                    return (enabled, confirmation)
                }
            }
            index += 1
        }
        return nil
    }

    private func profileDNSOverrideState(workspace: WorkspaceInfo) -> Bool? {
        guard let settings = profileDNSOverrideSettings(workspace: workspace),
              let enabled = settings.enabled else {
            return nil
        }
        guard enabled else { return false }
        guard let context = try? dnsOverrideContext(workspace: workspace) else {
            return nil
        }
        guard let expected = context.expectedConfirmation else {
            return true
        }
        return settings.confirmation == expected
    }

    private func existing(_ url: URL, fileManager: FileManager) -> URL? {
        fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func enableProfileDNSOverride(
        vergeURL: URL,
        profileUID: String,
        confirmation: String?
    ) throws -> (text: String, changed: Bool, changes: Int) {
        var text = try String(contentsOf: vergeURL, encoding: .utf8)
        var changes = 0
        let ensured = try ensureDNSOverrideBlock(
            text: text,
            profileUID: profileUID
        )
        text = ensured.text
        changes += ensured.changes
        let enabled = try setDNSOverrideValue(
            text: text,
            profileUID: profileUID,
            key: "enabled",
            value: "true"
        )
        text = enabled.text
        changes += enabled.changes
        let confirmed = try setDNSOverrideValue(
            text: text,
            profileUID: profileUID,
            key: "confirmation",
            value: confirmation
        )
        text = confirmed.text
        changes += confirmed.changes
        return (text, changes > 0, changes)
    }

    private func ensureDNSOverrideBlock(
        text: String,
        profileUID: String
    ) throws -> (text: String, changes: Int) {
        let source = try YAMLSource(text: text)
        var lines = source.lines
        guard let section = source.section(named: "profile_dns_settings") else {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append(contentsOf: [
                "profile_dns_settings:",
                "  \(profileUID):"
            ])
            return (lines.joined(separator: source.lineEnding), 2)
        }
        guard let bodyIndent = source.bodyIndent(in: section) else {
            lines.insert(
                "  \(profileUID):",
                at: min(section.lowerBound, lines.count)
            )
            return (lines.joined(separator: source.lineEnding), 1)
        }
        let exists = section.contains { index in
            let line = source.line(index)
            guard !line.isIgnorable,
                  line.indent == bodyIndent,
                  !line.startsSequenceItem,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                return false
            }
            return YAMLSource.unquote(
                split.key.trimmingCharacters(in: .whitespaces)
            ) == profileUID
        }
        guard !exists else { return (text, 0) }
        let indent = String(repeating: " ", count: bodyIndent)
        lines.insert(
            "\(indent)\(profileUID):",
            at: min(section.lowerBound, lines.count)
        )
        return (lines.joined(separator: source.lineEnding), 1)
    }

    private func setDNSOverrideValue(
        text: String,
        profileUID: String,
        key: String,
        value: String?
    ) throws -> (text: String, changes: Int) {
        let source = try YAMLSource(text: text)
        var lines = source.lines
        guard let section = source.section(named: "profile_dns_settings"),
              let bodyIndent = source.bodyIndent(in: section),
              let profileLine = section.first(where: { index in
                  let line = source.line(index)
                  guard !line.isIgnorable,
                        line.indent == bodyIndent,
                        !line.startsSequenceItem,
                        let split = YAMLSource.splitKeyValue(line.content) else {
                      return false
                  }
                  return YAMLSource.unquote(
                    split.key.trimmingCharacters(in: .whitespaces)
                  ) == profileUID
              }) else {
            throw ConfigParseError.unreadable(
                "无法定位 Clash Verge DNS 覆写设置块。"
            )
        }

        var blockEnd = section.upperBound
        var childIndent = bodyIndent + 2
        var cursor = profileLine + 1
        while cursor < section.upperBound {
            let line = source.line(cursor)
            if !line.isIgnorable, line.indent <= bodyIndent {
                blockEnd = cursor
                break
            }
            if !line.isIgnorable, childIndent == bodyIndent + 2 {
                childIndent = line.indent
            }
            cursor += 1
        }

        let existing = (profileLine + 1)..<blockEnd
        if let lineIndex = existing.first(where: { index in
            let line = source.line(index)
            guard !line.isIgnorable,
                  !line.startsSequenceItem,
                  line.indent == childIndent,
                  let split = YAMLSource.splitKeyValue(line.content) else {
                return false
            }
            return YAMLSource.unquote(
                split.key.trimmingCharacters(in: .whitespaces)
            ) == key
        }) {
            let line = source.line(lineIndex)
            guard let split = YAMLSource.splitKeyValue(line.content) else {
                return (text, 0)
            }
            if let value {
                let content = line.content as NSString
                let valueRange = content.range(of: split.value)
                if split.value.isEmpty {
                    lines[lineIndex] = String(repeating: " ", count: line.indent)
                        + "\(split.key): \(value)"
                    return (lines.joined(separator: source.lineEnding), 1)
                }
                guard valueRange.location != NSNotFound else {
                    return (text, 0)
                }
                let token = source.token(
                    from: lineIndex,
                    startingAt: line.indent + valueRange.location
                )
                guard let token else { return (text, 0) }
                let currentValue = YAMLSource.unquote(token.value)
                guard currentValue != value else { return (text, 0) }
                let ns = lines[lineIndex] as NSString
                lines[lineIndex] = ns.replacingCharacters(
                    in: NSRange(
                        location: token.start,
                        length: token.end - token.start
                    ),
                    with: value
                )
            } else {
                lines[lineIndex] = ""
            }
            return (lines.joined(separator: source.lineEnding), 1)
        }

        guard let value else { return (text, 0) }
        var insertAt = profileLine + 1
        var scan = profileLine + 1
        while scan < blockEnd {
            let line = source.line(scan)
            if !line.isIgnorable, line.indent >= childIndent {
                insertAt = scan + 1
            }
            scan += 1
        }
        lines.insert(
            "\(String(repeating: " ", count: childIndent))\(key): \(value)",
            at: min(insertAt, lines.count)
        )
        return (lines.joined(separator: source.lineEnding), 1)
    }

    private func writeWithBackups(
        _ writes: [(url: URL, data: Data)]
    ) throws -> ([URL], [FileBackup]) {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        var changed: [URL] = []
        var backups: [FileBackup] = []

        for write in writes {
            let original = write.url
            let backup = original
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "\(original.lastPathComponent).dnsleakguard-backup.\(stamp)"
                )
            if fileManager.fileExists(atPath: original.path) {
                var destination = backup
                if fileManager.fileExists(atPath: destination.path) {
                    destination = URL(
                        fileURLWithPath: backup.path + "-" + UUID().uuidString.prefix(6)
                    )
                }
                try fileManager.copyItem(at: original, to: destination)
                backups.append(FileBackup(original: original, backup: destination))
            }
            try write.data.write(to: original, options: [.atomic])
            changed.append(original)
        }
        return (changed, backups)
    }

    private func deduplicateWrites(
        _ writes: [(url: URL, data: Data)]
    ) -> [(url: URL, data: Data)] {
        var order: [URL] = []
        var byURL: [URL: Data] = [:]
        for write in writes {
            if byURL[write.url] == nil {
                order.append(write.url)
            }
            byURL[write.url] = write.data
        }
        return order.compactMap { url in
            byURL[url].map { (url, $0) }
        }
    }

    private func uniqueStrings(_ strings: [String]) -> [String] {
        var seen: Set<String> = []
        return strings.filter { seen.insert($0).inserted }
    }
}
