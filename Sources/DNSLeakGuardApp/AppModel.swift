import AppKit
import Combine
import DNSLeakCore
import Foundation

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case findings
    case liveTests
    case traffic
    case repair
    case routing
    case protection
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .findings: "诊断"
        case .liveTests: "在线测漏"
        case .traffic: "访问链路"
        case .repair: "修复"
        case .routing: "规则模式"
        case .protection: "实时守护"
        case .permissions: "权限与说明"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2.fill"
        case .findings: "list.bullet.clipboard.fill"
        case .liveTests: "globe.asia.australia.fill"
        case .traffic: "point.3.connected.trianglepath.dotted"
        case .repair: "wrench.and.screwdriver.fill"
        case .routing: "arrow.triangle.branch"
        case .protection: "shield.lefthalf.filled"
        case .permissions: "lock.shield.fill"
        }
    }
}

enum ProtectionRuntimeState: Equatable {
    case off
    case starting
    case active
    case repairing
    case attention
    case paused
    case unavailable

    var label: String {
        switch self {
        case .off: "未启用"
        case .starting: "正在启用"
        case .active: "守护中"
        case .repairing: "正在恢复"
        case .attention: "需要处理"
        case .paused: "已暂停"
        case .unavailable: "等待 Clash Verge"
        }
    }

    var isProtecting: Bool {
        self == .active || self == .repairing || self == .attention
    }
}

struct ProtectionEvent: Identifiable {
    enum Kind {
        case armed
        case change
        case repaired
        case repairFailed
        case paused
        case resumed
        case disabled

        var symbol: String {
            switch self {
            case .armed: "checkmark.shield.fill"
            case .change: "arrow.triangle.2.circlepath"
            case .repaired: "wand.and.stars"
            case .repairFailed: "exclamationmark.triangle.fill"
            case .paused: "pause.fill"
            case .resumed: "play.fill"
            case .disabled: "shield.slash.fill"
            }
        }
    }

    let id = UUID()
    let date: Date
    let kind: Kind
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Activity: Equatable {
        case starting
        case scanning
        case fixing
        case testing
        case routing
        case idle

        var isBusy: Bool {
            self != .idle
        }

        var label: String {
            switch self {
            case .starting: "正在初始化"
            case .scanning: "正在检测"
            case .fixing: "正在修复"
            case .testing: "正在在线复验"
            case .routing: "正在写入规则"
            case .idle: "就绪"
            }
        }
    }

    private enum DefaultsKey {
        static let protectionEnabled = "protection.enabled"
        static let protectionMode = "protection.mode"
        static let fallbackScanMinutes = "protection.fallbackScanMinutes"
        static let persistDNSOverride = "repair.persistDNSOverride"
        static let selectedProxyGroup = "repair.proxyGroup"
        static let notificationsEnabled = "notifications.enabled"
        static let removePlaintextDNS = "fix.removePlaintextDNS"
        static let bindDNSToProxy = "fix.bindDNSToProxy"
        static let enableMihomoDNS = "fix.enableMihomoDNS"
        static let fixDNSKeyTypos = "fix.fixDNSKeyTypos"
        static let addNoResolve = "fix.addNoResolve"
        static let selectedProviders = "live.selectedProviders"
        static let ruleIncludeWhatsApp = "rules.whatsapp"
        static let ruleIncludeMeta = "rules.meta"
        static let ruleIncludeLocalDirect = "rules.localDirect"
        static let ruleIncludeLoyalsoldierProxy = "rules.loyalsoldierProxy"
        static let ruleIncludeLoyalsoldierPrivate = "rules.loyalsoldierPrivate"
        static let ruleIncludeLoyalsoldierDirect = "rules.loyalsoldierDirect"
        static let ruleForceProxyFallback = "rules.forceProxyFallback"
        static let ensureFinalMatch = "rules.ensureFinalMatch"
    }

    @Published var workspace: WorkspaceInfo?
    @Published var analysis: ConfigAnalysis?
    @Published var liveResult: LiveDNSTestResult?
    @Published var selectedProviders: Set<DNSLeakProviderID>
    @Published var providerResults: [DNSLeakProviderResult] = []
    @Published var providerProgressText = "尚未运行多站点检测"
    @Published var runtimeStatus: ClashRuntimeStatus?
    @Published var health: WorkspaceHealth?
    @Published var activity: Activity = .starting
    @Published var progressText = "正在连接 Clash Verge…"
    @Published var errorMessage: String?
    @Published var lastReport: FixApplicationReport?
    @Published var selection: FixSelection
    @Published var selectedProxyGroup: String?
    @Published var persistDNSOverride: Bool
    @Published var lastUpdated: Date?
    @Published var showLiveDetails = false
    @Published var dashboardSection: DashboardSection = .overview
    @Published var rulePreview: ClashRulePreview?
    @Published var ruleReport: ClashRuleApplicationReport?
    @Published var ruleIncludeWhatsApp: Bool
    @Published var ruleIncludeMeta: Bool
    @Published var ruleIncludeLocalDirect: Bool
    @Published var ruleIncludeLoyalsoldierProxy: Bool
    @Published var ruleIncludeLoyalsoldierPrivate: Bool
    @Published var ruleIncludeLoyalsoldierDirect: Bool
    @Published var ruleForceProxyFallback: Bool
    @Published var ensureFinalMatch: Bool
    @Published var liveDomains: [ClashLiveDomain] = []
    @Published var liveProxyGroups: [ClashLiveProxyGroup] = []
    @Published var liveControllerRules: [ClashLiveRule] = []
    @Published var liveRuleProviders: [ClashLiveRuleProvider] = []
    @Published var liveControllerTargets = Set<String>()
    @Published var liveTrafficStreaming = false
    @Published var liveTrafficConnected = false
    @Published var liveTrafficError: String?
    @Published var liveActionMessage: String?
    @Published var liveTrafficUpdatedAt: Date?
    @Published var ruleDraftDocument: ClashRuleDocument?
    @Published var ruleDraftRules: [EditableClashRule] = []
    @Published var ruleDraftIssues: [ClashRuleValidationIssue] = []
    @Published var ruleDraftRenderedText: String?
    @Published var ruleDraftIsLoading = false
    @Published var ruleDraftIsValidated = false
    @Published var ruleDraftIsDirty = false
    @Published var ruleDraftExportMessage: String?
    @Published var ruleEditorReport: ClashRuleApplyReport?
    @Published var upstreamSnapshot: LoyalsoldierRuleRepositorySnapshot?
    @Published var upstreamIsLoading = false
    @Published var upstreamStatusMessage: String?
    @Published var upstreamCachePath = ""
    @Published var upstreamSyncedAt: Date?

    @Published var protectionEnabled: Bool
    @Published var protectionMode: ProtectionMode
    @Published var protectionState: ProtectionRuntimeState = .off
    @Published var protectionStatusText = "实时守护未启用"
    @Published var protectionPausedUntil: Date?
    @Published var protectionAutoRepairBlockedUntil: Date?
    @Published var protectionEvents: [ProtectionEvent] = []
    @Published var lastProtectionCheck: Date?
    @Published var protectionRepairCount = 0
    @Published var fallbackScanMinutes: Int

    @Published var notificationsEnabled: Bool
    @Published var notificationsAuthorized = false
    @Published var notificationStatusText = "未请求"
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginStatusText = "未启用"
    @Published var memoryMegabytes: Double = 0

    private let defaults: UserDefaults
    private let service = ClashVergeService()
    private let ruleService = ClashRuleService()
    private let liveService = ClashLiveService()
    private let ruleEditorService = ClashRuleEditorService()
    private let upstreamService = LoyalsoldierRuleRepositoryService()
    private var changeMonitor: DirectoryChangeMonitor?
    private var pendingProtectionScan: DispatchWorkItem?
    private var protectionPauseTimer: Timer?
    private var protectionFallbackTimer: Timer?
    private var memoryTimer: Timer?
    private var isProtectionReconciling = false
    private var repairTimestamps: [Date] = []
    private var lastNotificationAt = Date.distantPast
    private var lastReconciledFingerprint: String?
    private var trafficAccumulator = ClashTrafficAccumulator()
    private var liveTrafficTask: Task<Void, Never>?
    private var lastLiveProxyRefresh = Date.distantPast
    private var lastLiveRuleRefresh = Date.distantPast
    private var deepLinkActionTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selection = FixSelection(
            removePlaintextDNS: defaults.object(forKey: DefaultsKey.removePlaintextDNS) as? Bool ?? true,
            bindDNSToProxy: defaults.object(forKey: DefaultsKey.bindDNSToProxy) as? Bool ?? true,
            enableMihomoDNS: defaults.object(forKey: DefaultsKey.enableMihomoDNS) as? Bool ?? true,
            fixDNSKeyTypos: defaults.object(forKey: DefaultsKey.fixDNSKeyTypos) as? Bool ?? true,
            addNoResolve: defaults.bool(forKey: DefaultsKey.addNoResolve)
        )
        self.selectedProxyGroup = defaults.string(forKey: DefaultsKey.selectedProxyGroup)
        self.persistDNSOverride = defaults.object(forKey: DefaultsKey.persistDNSOverride) as? Bool ?? true
        self.protectionEnabled = defaults.bool(forKey: DefaultsKey.protectionEnabled)
        self.protectionMode = defaults.string(forKey: DefaultsKey.protectionMode)
            .flatMap(ProtectionMode.init(rawValue:)) ?? .notifyOnly
        self.fallbackScanMinutes = defaults.object(forKey: DefaultsKey.fallbackScanMinutes) as? Int ?? 5
        self.notificationsEnabled = defaults.bool(forKey: DefaultsKey.notificationsEnabled)
        if let stored = defaults.array(forKey: DefaultsKey.selectedProviders)
            as? [String] {
            self.selectedProviders = Set(
                stored.compactMap(DNSLeakProviderID.init(rawValue:))
            )
        } else {
            self.selectedProviders = Set(DNSLeakProviderID.allCases)
        }
        self.ruleIncludeWhatsApp =
            defaults.object(forKey: DefaultsKey.ruleIncludeWhatsApp) as? Bool ?? true
        self.ruleIncludeMeta =
            defaults.object(forKey: DefaultsKey.ruleIncludeMeta) as? Bool ?? false
        self.ruleIncludeLocalDirect =
            defaults.object(forKey: DefaultsKey.ruleIncludeLocalDirect) as? Bool ?? true
        self.ruleIncludeLoyalsoldierProxy =
            defaults.object(forKey: DefaultsKey.ruleIncludeLoyalsoldierProxy) as? Bool ?? true
        self.ruleIncludeLoyalsoldierPrivate =
            defaults.object(forKey: DefaultsKey.ruleIncludeLoyalsoldierPrivate) as? Bool ?? true
        self.ruleIncludeLoyalsoldierDirect =
            defaults.object(forKey: DefaultsKey.ruleIncludeLoyalsoldierDirect) as? Bool ?? false
        self.ruleForceProxyFallback =
            defaults.object(forKey: DefaultsKey.ruleForceProxyFallback) as? Bool ?? false
        self.ensureFinalMatch =
            defaults.object(forKey: DefaultsKey.ensureFinalMatch) as? Bool ?? true
        self.launchAtLoginEnabled = LaunchAtLogin.isEnabled
        self.launchAtLoginStatusText = LaunchAtLogin.statusText
        self.memoryMegabytes = ProcessFootprint.residentMegabytes()
        self.upstreamCachePath = upstreamService.cachePath
        if let cached = try? upstreamService.loadCachedSnapshot() {
            self.upstreamSnapshot = cached
            self.upstreamSyncedAt = cached.fetchedAt
            self.upstreamStatusMessage = "已载入本地缓存；点击“检查更新”读取 GitHub 最新状态。"
        }

        Task {
            await bootstrap()
            await refreshNotificationAuthorization()
        }
    }

    var isBusy: Bool {
        activity.isBusy
    }

    var score: Int {
        var value = analysis?.score ?? 0
        if hasMultipleResolverPaths {
            value = max(0, value - 18)
        }
        return value
    }

    var headline: String {
        guard analysis != nil else { return "尚未完成检测" }
        if analysis?.findings.contains(where: {
            $0.category == .confirmedLeak && $0.severity >= .high
        }) == true {
            return "发现需要立即处理的 DNS 风险"
        }
        if hasMultipleResolverPaths {
            return "检测到多解析器路径，需要复核"
        }
        if score >= 90 {
            return "DNS 防护状态良好"
        }
        return "存在可加固项目"
    }

    var riskCount: Int {
        analysis?.findings.filter {
            $0.category == .confirmedLeak || $0.category == .possibleLeak
        }.count ?? 0
    }

    var configErrorCount: Int {
        analysis?.findings.filter { $0.category == .configError }.count ?? 0
    }

    var actionableOptions: [FixOptionType] {
        FixOptionType.allCases.filter { option in
            (analysis?.findingCount(for: option) ?? 0) > 0
        }
    }

    var selectedProtectionOptionCount: Int {
        FixOptionType.allCases.filter(selection.isEnabled).count
    }

    var nativeProviderResults: [DNSLeakProviderResult] {
        providerResults.filter { $0.provider.isNativeResult }
    }

    var providerResultsInDisplayOrder: [DNSLeakProviderResult] {
        DNSLeakProviderID.allCases.compactMap(providerResult(for:))
    }

    var hasMultipleResolverPaths: Bool {
        providerResults.contains { $0.outcome == .multiplePaths }
            || liveResult?.outcome == .multipleResolverPaths
    }

    var providerResolverCount: Int {
        Set(nativeProviderResults.flatMap { $0.observations.map(\.ip) }).count
    }

    var providerTestedCount: Int {
        providerResults.count
    }

    var providerSelectedNativeCount: Int {
        selectedProviders.filter(\.isNativeResult).count
    }

    var ruleOptions: ClashRuleOptions? {
        guard let group = selectedProxyGroup else { return nil }
        return ClashRuleOptions(
            proxyGroup: group,
            includeWhatsApp: ruleIncludeWhatsApp,
            includeMeta: ruleIncludeMeta,
            includeLocalDirect: ruleIncludeLocalDirect,
            includeLoyalsoldierProxy: ruleIncludeLoyalsoldierProxy,
            includeLoyalsoldierPrivate: ruleIncludeLoyalsoldierPrivate,
            includeLoyalsoldierDirect: ruleIncludeLoyalsoldierDirect,
            forceProxyFallback: ruleForceProxyFallback,
            ensureFinalMatch: ensureFinalMatch
        )
    }

    var isProtectionPaused: Bool {
        guard let until = protectionPausedUntil else { return false }
        return until > Date()
    }

    var protectionIconName: String {
        switch protectionState {
        case .off: "shield.slash"
        case .starting: "shield"
        case .active: "checkmark.shield.fill"
        case .repairing: "arrow.triangle.2.circlepath"
        case .attention: "exclamationmark.shield.fill"
        case .paused: "pause.circle.fill"
        case .unavailable: "questionmark.circle"
        }
    }

    func optionCount(_ option: FixOptionType) -> Int {
        analysis?.findingCount(for: option) ?? 0
    }

    func providerResult(
        for provider: DNSLeakProviderID
    ) -> DNSLeakProviderResult? {
        providerResults.first { $0.provider == provider }
    }

    // MARK: - Detection and manual repair

    func bootstrap() async {
        if activity == .starting, workspace != nil {
            return
        }
        activity = .starting
        errorMessage = nil
        progressText = "正在连接 Clash Verge…"
        workspace = await service.discover()
        guard let workspace else {
            activity = .idle
            errorMessage = "没有找到 Clash Verge 的活动配置目录。请先运行 Clash Verge 并应用一次配置。"
            progressText = "未找到 Clash Verge"
            if protectionEnabled {
                protectionState = .unavailable
                protectionStatusText = "等待 Clash Verge 配置目录"
            }
            return
        }
        do {
            try await refreshStatic()
            await refreshRuntimeAndHealth(workspace: workspace)
            lastUpdated = Date()
            lastProtectionCheck = Date()
            activity = .idle
            progressText = "就绪"
            if protectionEnabled {
                startProtectionMonitor()
            } else {
                protectionState = .off
                protectionStatusText = "实时守护未启用"
            }
        } catch {
            fail(error)
            if protectionEnabled {
                protectionState = .attention
                protectionStatusText = "配置读取失败"
            }
        }
    }

    func runDetection() async {
        guard !isBusy, protectionState != .repairing else { return }
        activity = .scanning
        errorMessage = nil
        progressText = "正在分析 DNS 结构与规则链…"
        do {
            workspace = await service.discover() ?? workspace
            guard let workspace else {
                throw SimpleError("Clash Verge 配置目录不可用。")
            }
            try await refreshStatic()
            activity = .testing
            await runSelectedProvidersInternal()
            await refreshRuntimeAndHealth(workspace: workspace)
            lastUpdated = Date()
            lastProtectionCheck = Date()
            activity = .idle
            progressText = "检测完成 · \(providerResults.count) 个站点"
            showLiveDetails = hasMultipleResolverPaths
        } catch {
            fail(error)
        }
    }

    func handleDeepLink(_ link: DNSLeakGuardDeepLink) {
        if let section = link.section {
            dashboardSection = dashboardSection(for: section)
        }

        switch link {
        case .navigate:
            break
        case .scan:
            scheduleDeepLinkAction {
                await self.runDetectionAfterStartup()
            }
        case let .onlineTest(providers):
            if let providers {
                selectedProviders = Set(providers)
                persistProviderSelection()
            }
            guard !selectedProviders.isEmpty else {
                errorMessage = "深链未指定测漏站点，当前也没有已勾选站点。"
                return
            }
            scheduleDeepLinkAction {
                await self.runOnlineTestAfterStartup()
            }
        }
    }

    func navigate(to section: DashboardSection) {
        dashboardSection = section
    }

    func runOneClick() async {
        guard !isBusy, protectionState != .repairing else { return }
        activity = .fixing
        errorMessage = nil
        lastReport = nil
        progressText = "正在检测配置…"
        do {
            workspace = await service.discover() ?? workspace
            guard let workspace else {
                throw SimpleError("Clash Verge 配置目录不可用。")
            }
            try await refreshStatic()
            progressText = "正在按勾选项修复并重载配置…"
            let service = service
            let selection = selection
            let proxyGroup = selectedProxyGroup
            let persistDNSOverride = persistDNSOverride
            let report = try await Task.detached(priority: .userInitiated) {
                try await service.apply(
                    workspace: workspace,
                    selection: selection,
                    proxyGroup: proxyGroup,
                    persistDNSOverride: persistDNSOverride
                )
            }.value
            lastReport = report
            self.workspace = await service.discover() ?? workspace
            try await refreshStatic()
            activity = .testing
            progressText = "配置已写入，正在在线复验 DNS 出口…"
            try await Task.sleep(nanoseconds: 500_000_000)
            await runSelectedProvidersInternal()
            if let workspace = self.workspace {
                await refreshRuntimeAndHealth(workspace: workspace)
            }
            lastUpdated = Date()
            lastProtectionCheck = Date()
            activity = .idle
            progressText = report.reloadSucceeded ? "修复完成并已重载" : "修复已写入，等待 Clash Verge 重载"
        } catch {
            fail(error)
        }
    }

    func applySelectedOnly() async {
        guard !isBusy, protectionState != .repairing else { return }
        activity = .fixing
        errorMessage = nil
        lastReport = nil
        progressText = "正在应用已勾选修复项…"
        do {
            guard let workspace else {
                throw SimpleError("Clash Verge 配置目录不可用。")
            }
            let service = service
            let selection = selection
            let proxyGroup = selectedProxyGroup
            let persistDNSOverride = persistDNSOverride
            let report = try await Task.detached(priority: .userInitiated) {
                try await service.apply(
                    workspace: workspace,
                    selection: selection,
                    proxyGroup: proxyGroup,
                    persistDNSOverride: persistDNSOverride
                )
            }.value
            lastReport = report
            self.workspace = await service.discover() ?? workspace
            try await refreshStatic()
            if let workspace = self.workspace {
                await refreshRuntimeAndHealth(workspace: workspace)
            }
            lastUpdated = Date()
            lastProtectionCheck = Date()
            activity = .idle
            progressText = "修复完成"
        } catch {
            fail(error)
        }
    }

    func runLiveTestOnly() async {
        guard !isBusy else { return }
        guard !selectedProviders.isEmpty else {
            errorMessage = "请至少勾选一个 DNS 测漏站点。"
            return
        }
        activity = .testing
        errorMessage = nil
        progressText = "正在并发检测所选站点…"
        await runSelectedProvidersInternal()
        lastUpdated = Date()
        activity = .idle
        progressText = "多站点检测完成"
    }

    func setProviderSelected(
        _ provider: DNSLeakProviderID,
        enabled: Bool
    ) {
        if enabled {
            selectedProviders.insert(provider)
        } else {
            selectedProviders.remove(provider)
        }
        persistProviderSelection()
    }

    func selectAllProviders() {
        selectedProviders = Set(DNSLeakProviderID.allCases)
        persistProviderSelection()
    }

    func clearSelectedProviders() {
        selectedProviders.removeAll()
        persistProviderSelection()
    }

    func openProviderPage(_ provider: DNSLeakProviderID) {
        NSWorkspace.shared.open(provider.pageURL)
    }

    func set(_ option: FixOptionType, enabled: Bool) {
        selection = selection.set(option, enabled: enabled)
        defaults.set(enabled, forKey: defaultsKey(for: option))
        if protectionEnabled {
            updateProtectionStatusForCurrentPolicy()
        }
    }

    func setPersistDNSOverride(_ enabled: Bool) {
        persistDNSOverride = enabled
        defaults.set(enabled, forKey: DefaultsKey.persistDNSOverride)
    }

    func setSelectedProxyGroup(_ name: String?) {
        selectedProxyGroup = name
        if let name {
            defaults.set(name, forKey: DefaultsKey.selectedProxyGroup)
        } else {
            defaults.removeObject(forKey: DefaultsKey.selectedProxyGroup)
        }
        invalidateRulePreview()
    }

    // MARK: - Clash rule mode

    func setRuleIncludeWhatsApp(_ enabled: Bool) {
        ruleIncludeWhatsApp = enabled
        defaults.set(enabled, forKey: DefaultsKey.ruleIncludeWhatsApp)
        invalidateRulePreview()
    }

    func setRuleIncludeMeta(_ enabled: Bool) {
        ruleIncludeMeta = enabled
        defaults.set(enabled, forKey: DefaultsKey.ruleIncludeMeta)
        invalidateRulePreview()
    }

    func setRuleIncludeLocalDirect(_ enabled: Bool) {
        ruleIncludeLocalDirect = enabled
        defaults.set(enabled, forKey: DefaultsKey.ruleIncludeLocalDirect)
        invalidateRulePreview()
    }

    func setRuleIncludeLoyalsoldierProxy(_ enabled: Bool) {
        ruleIncludeLoyalsoldierProxy = enabled
        defaults.set(enabled, forKey: DefaultsKey.ruleIncludeLoyalsoldierProxy)
        invalidateRulePreview()
    }

    func setRuleIncludeLoyalsoldierPrivate(_ enabled: Bool) {
        ruleIncludeLoyalsoldierPrivate = enabled
        defaults.set(enabled, forKey: DefaultsKey.ruleIncludeLoyalsoldierPrivate)
        invalidateRulePreview()
    }

    func setRuleIncludeLoyalsoldierDirect(_ enabled: Bool) {
        ruleIncludeLoyalsoldierDirect = enabled
        defaults.set(enabled, forKey: DefaultsKey.ruleIncludeLoyalsoldierDirect)
        invalidateRulePreview()
    }

    func setRuleForceProxyFallback(_ enabled: Bool) {
        ruleForceProxyFallback = enabled
        if enabled {
            ruleIncludeLoyalsoldierDirect = true
            defaults.set(true, forKey: DefaultsKey.ruleIncludeLoyalsoldierDirect)
        }
        defaults.set(enabled, forKey: DefaultsKey.ruleForceProxyFallback)
        invalidateRulePreview()
    }

    func setEnsureFinalMatch(_ enabled: Bool) {
        ensureFinalMatch = enabled
        defaults.set(enabled, forKey: DefaultsKey.ensureFinalMatch)
        invalidateRulePreview()
    }

    func refreshRulePreview() async {
        guard let workspace, let analysis else {
            rulePreview = nil
            return
        }
        if selectedProxyGroup == nil {
            setSelectedProxyGroup(analysis.suggestedProxyGroup)
        }
        guard let options = ruleOptions else {
            rulePreview = nil
            return
        }
        do {
            let ruleService = ruleService
            rulePreview = try await Task.detached(priority: .userInitiated) {
                try ruleService.preview(
                    workspace: workspace,
                    analysis: analysis,
                    options: options
                )
            }.value
        } catch {
            errorMessage = error.localizedDescription
            rulePreview = nil
        }
    }

    func applyRulePlan() async {
        guard !isBusy, protectionState != .repairing else { return }
        guard let workspace, let analysis, let options = ruleOptions else {
            errorMessage = "请先完成配置扫描并选择代理组。"
            return
        }
        activity = .routing
        errorMessage = nil
        ruleReport = nil
        progressText = "正在写入 Merge 规则并同步活动配置…"
        do {
            let ruleService = ruleService
            let report = try await Task.detached(priority: .userInitiated) {
                try await ruleService.apply(
                    workspace: workspace,
                    analysis: analysis,
                    options: options
                )
            }.value
            ruleReport = report
            let discovered = await service.discover() ?? workspace
            self.workspace = discovered
            try await refreshStatic()
            await refreshRuntimeAndHealth(workspace: discovered)
            await refreshRulePreview()
            lastUpdated = Date()
            lastProtectionCheck = Date()
            activity = .idle
            progressText = report.reloadSucceeded
                ? "规则已写入、持久化并重载"
                : "规则已写入，等待 Clash Verge 重载"
        } catch {
            fail(error)
        }
    }

    private func invalidateRulePreview() {
        rulePreview = nil
        ruleReport = nil
    }

    // MARK: - Live traffic and rule workbench

    func startLiveTrafficMonitor() {
        guard liveTrafficTask == nil else { return }
        liveTrafficStreaming = true
        liveTrafficError = nil
        liveTrafficTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshLiveTraffic()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                await self.refreshLiveTraffic()
            }
        }
    }

    func stopLiveTrafficMonitor() {
        liveTrafficTask?.cancel()
        liveTrafficTask = nil
        liveTrafficStreaming = false
        liveTrafficConnected = false
    }

    func refreshLiveTraffic() async {
        guard let socket = await resolveLiveSocket() else {
            liveTrafficConnected = false
            liveTrafficError = "未找到运行中的 mihomo 控制接口。"
            return
        }
        do {
            let connections = try await liveService.connections(socket: socket)
            let now = Date()
            liveDomains = trafficAccumulator.ingest(connections, now: now)
            liveTrafficUpdatedAt = now
            liveTrafficConnected = true
            liveTrafficError = nil

            if now.timeIntervalSince(lastLiveProxyRefresh) >= 5 {
                lastLiveProxyRefresh = now
                if let snapshot = try? await liveService.proxies(socket: socket) {
                    liveProxyGroups = snapshot.groups
                    liveControllerTargets = snapshot.targetNames
                }
            }
            if now.timeIntervalSince(lastLiveRuleRefresh) >= 10 {
                lastLiveRuleRefresh = now
                await refreshLiveRulesAndProviders(socket: socket)
            }
        } catch {
            liveTrafficConnected = false
            liveTrafficError = error.localizedDescription
        }
    }

    func loadRuleDraft(force: Bool = false) async {
        if !force, ruleDraftDocument != nil {
            return
        }
        guard let workspace else {
            errorMessage = "Clash Verge 配置目录不可用。"
            return
        }
        ruleDraftIsLoading = true
        defer { ruleDraftIsLoading = false }
        do {
            let editor = ruleEditorService
            let document = try await Task.detached(priority: .userInitiated) {
                try editor.load(workspace: workspace)
            }.value
            let hits = Dictionary(
                grouping: liveControllerRules,
                by: { "\($0.type)|\($0.payload)|\($0.target)" }
            ).mapValues { rows in
                rows.reduce(0) { $0 + $1.hitCount }
            }
            var rules = document.rules
            for index in rules.indices {
                let key = "\(rules[index].type)|\(rules[index].payload)|\(rules[index].target)"
                rules[index].hitCount = hits[key] ?? 0
            }
            ruleDraftDocument = document
            ruleDraftRules = rules
            ruleDraftIssues = []
            ruleDraftRenderedText = nil
            ruleDraftIsValidated = false
            ruleDraftIsDirty = false
            ruleDraftExportMessage = nil
        } catch {
            errorMessage = "无法载入规则草稿：\(error.localizedDescription)"
        }
    }

    func validateRuleDraft() async -> Bool {
        guard let document = ruleDraftDocument else {
            errorMessage = "请先载入当前配置。"
            return false
        }
        let rules = ruleDraftRules
        let targets = liveControllerTargets
        do {
            let editor = ruleEditorService
            let validation = try await Task.detached(priority: .userInitiated) {
                try editor.prepare(
                    document: document,
                    rules: rules,
                    availableTargets: targets
                )
            }.value
            ruleDraftIssues = validation.issues
            ruleDraftRenderedText = validation.text
            ruleDraftIsValidated = true
            return !validation.hasErrors
        } catch {
            errorMessage = "规则校验失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func addRuleFromLiveHost(_ host: String, target: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "未知目标" else { return false }
        let rule: EditableClashRule
        if trimmed.contains(":") {
            rule = EditableClashRule(
                type: "IP-CIDR6",
                payload: "\(trimmed)/128",
                target: target
            )
        } else if isIPv4Literal(trimmed) {
            rule = EditableClashRule(
                type: "IP-CIDR",
                payload: "\(trimmed)/32",
                target: target
            )
        } else {
            rule = EditableClashRule(
                type: "DOMAIN-SUFFIX",
                payload: trimmed,
                target: target
            )
        }
        let normalized = rule.text.lowercased()
        guard !ruleDraftRules.contains(where: {
            $0.text.lowercased() == normalized
        }) else {
            ruleDraftExportMessage = "该规则已存在：\(rule.text)"
            return false
        }
        let insertAt = ruleDraftRules.firstIndex(where: \.isTerminalMatch)
            ?? ruleDraftRules.endIndex
        ruleDraftRules.insert(rule, at: insertAt)
        markRuleDraftDirty()
        ruleDraftExportMessage =
            "已生成草稿：\(rule.text) · 尚未生效，需点“应用到 Clash”"
        return true
    }

    func deleteRuleDraftRule(_ id: UUID) {
        guard let index = ruleDraftRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        ruleDraftRules.remove(at: index)
        markRuleDraftDirty()
    }

    func moveRuleDraftRule(_ id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = ruleDraftRules.firstIndex(where: { $0.id == id }),
              let target = ruleDraftRules.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        let rule = ruleDraftRules.remove(at: from)
        let insertion = from < target ? target - 1 : target
        ruleDraftRules.insert(rule, at: max(0, min(insertion, ruleDraftRules.count)))
        markRuleDraftDirty()
    }

    func moveRuleDraftRule(_ id: UUID, offset: Int) {
        guard let from = ruleDraftRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        let to = from + offset
        guard ruleDraftRules.indices.contains(to) else { return }
        let rule = ruleDraftRules.remove(at: from)
        ruleDraftRules.insert(rule, at: to)
        markRuleDraftDirty()
    }

    func setRuleDraftTarget(_ id: UUID, target: String) {
        guard let index = ruleDraftRules.firstIndex(where: { $0.id == id }),
              ruleDraftRules[index].target != target else {
            return
        }
        ruleDraftRules[index].target = target
        markRuleDraftDirty()
    }

    func restoreRuleDraft() async {
        await loadRuleDraft(force: true)
    }

    func exportRuleDraft() async {
        guard await validateRuleDraft() else {
            errorMessage = "规则存在错误，已阻止导出。"
            return
        }
        guard let text = ruleDraftRenderedText else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clash-verge-rules.yaml"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            ruleDraftExportMessage = "已导出完整 YAML：\(url.path)"
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func applyRuleDraft() async {
        guard !isBusy else { return }
        guard await validateRuleDraft() else {
            errorMessage = "规则存在错误，已阻止写入。"
            return
        }
        guard let document = ruleDraftDocument,
              let text = ruleDraftRenderedText else {
            return
        }
        activity = .routing
        errorMessage = nil
        progressText = "正在写入完整规则并重载…"
        do {
            guard let socket = await resolveLiveSocket() else {
                throw SimpleError("未找到运行中的 mihomo 控制接口。")
            }
            let editor = ruleEditorService
            let report = try await Task.detached(priority: .userInitiated) {
                try await editor.apply(
                    document: document,
                    renderedText: text,
                    socket: socket
                )
            }.value
            ruleEditorReport = report
            self.workspace = await service.discover() ?? workspace
            if let workspace = self.workspace {
                try await refreshStatic()
                await refreshRuntimeAndHealth(workspace: workspace)
                await refreshLiveRulesAndProviders(socket: socket)
            }
            await loadRuleDraft(force: true)
            activity = .idle
            progressText = report.reloadSucceeded
                ? "完整规则已应用并重载"
                : "完整规则已写入，等待重载"
        } catch {
            fail(error)
        }
    }

    func selectLiveProxyMember(group groupName: String, member: String) async {
        guard let group = liveProxyGroups.first(where: { $0.name == groupName }) else {
            errorMessage = "出口组已不存在，请刷新控制器。"
            return
        }
        guard group.isUserSelectable else {
            errorMessage = "“\(groupName)”由内核自动选择节点，不能手动固定。"
            return
        }
        guard group.members.contains(where: { $0.name == member }) else {
            errorMessage = "节点不属于当前出口组，请刷新控制器后重试。"
            return
        }
        guard let socket = await resolveLiveSocket() else {
            errorMessage = "未找到运行中的 mihomo 控制接口。"
            return
        }
        do {
            try await liveService.selectProxyMember(
                socket: socket,
                group: groupName,
                member: member
            )
            await refreshLiveControllerData(socket: socket)
            liveActionMessage = "已将“\(groupName)”切换到“\(member)”。"
        } catch {
            errorMessage = "切换出口失败：\(error.localizedDescription)"
        }
    }

    func refreshLiveRuleProvider(_ name: String) async {
        guard let socket = await resolveLiveSocket() else {
            errorMessage = "未找到运行中的 mihomo 控制接口。"
            return
        }
        do {
            try await liveService.refreshRuleProvider(socket: socket, name: name)
            await refreshLiveControllerData(socket: socket)
            liveTrafficError = nil
            let count = liveRuleProviders.first(where: { $0.name == name })?.ruleCount
            liveActionMessage = count.map {
                "规则提供器“\(name)”已更新，共 \($0) 条。"
            } ?? "规则提供器“\(name)”已更新。"
        } catch {
            errorMessage = "更新规则提供器失败：\(error.localizedDescription)"
        }
    }

    func checkLoyalsoldierRuleRepository() async {
        guard !upstreamIsLoading else { return }
        upstreamIsLoading = true
        upstreamStatusMessage = "正在读取 Loyalsoldier 规则仓库…"
        defer { upstreamIsLoading = false }
        let previous = upstreamSnapshot
        do {
            let snapshot = try await upstreamService.fetch()
            upstreamSnapshot = snapshot
            upstreamCachePath = upstreamService.cachePath
            if let previous,
               previous.releaseCommitSHA != snapshot.releaseCommitSHA {
                upstreamStatusMessage =
                    "发现上游新提交：\(previous.shortCommitSHA) → \(snapshot.shortCommitSHA)"
            } else if previous == nil {
                upstreamStatusMessage =
                    "已读取 release@\(snapshot.shortCommitSHA) · \(snapshot.ruleCountLabel)"
            } else {
                upstreamStatusMessage =
                    "上游与上次检查一致：release@\(snapshot.shortCommitSHA)"
            }
        } catch {
            upstreamStatusMessage = "检查上游失败：\(error.localizedDescription)"
        }
    }

    func pullLoyalsoldierRuleUpdates() async {
        guard !upstreamIsLoading else { return }
        upstreamIsLoading = true
        upstreamStatusMessage = "正在拉取 private/direct/proxy 规则并刷新内核…"
        defer { upstreamIsLoading = false }
        do {
            let snapshot = try await upstreamService.fetch()
            let report = try await upstreamService.sync(snapshot: snapshot)
            upstreamSnapshot = snapshot
            upstreamCachePath = report.directory.path
            upstreamSyncedAt = report.syncedAt
            guard let socket = await resolveLiveSocket() else {
                upstreamStatusMessage =
                    "规则文件已保存，但未找到 mihomo 控制接口，未能刷新内核。"
                return
            }
            await refreshLiveControllerData(socket: socket)
            let providerNames = liveRuleProviders
                .map(\.name)
                .filter { $0.contains("loyalsoldier-") }
            if providerNames.isEmpty {
                upstreamStatusMessage =
                    "已拉取 release@\(snapshot.shortCommitSHA) 并保存规则文件；"
                    + "当前没有 Loyalsoldier 规则提供器，请先在“规则模式”启用。"
                return
            }
            var refreshed = 0
            var failures: [String] = []
            for name in providerNames {
                do {
                    try await liveService.refreshRuleProvider(
                        socket: socket,
                        name: name
                    )
                    refreshed += 1
                } catch {
                    failures.append(name)
                }
            }
            await refreshLiveControllerData(socket: socket)
            if failures.isEmpty {
                upstreamStatusMessage =
                    "已拉取 release@\(snapshot.shortCommitSHA)，"
                    + "并刷新 \(refreshed) 个规则提供器。"
            } else {
                upstreamStatusMessage =
                    "规则文件已保存，已刷新 \(refreshed) 个提供器；"
                    + "失败：\(failures.joined(separator: "、"))"
            }
        } catch {
            upstreamStatusMessage = "拉取规则更新失败：\(error.localizedDescription)"
        }
    }

    func openLoyalsoldierRuleRepository() {
        NSWorkspace.shared.open(LoyalsoldierRuleRepositoryService.repositoryURL)
    }

    func openLoyalsoldierRuleCache() {
        let url = URL(fileURLWithPath: upstreamCachePath)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(url)
    }

    func refreshLiveControllerNow() async {
        guard let socket = await resolveLiveSocket() else {
            liveTrafficError = "未找到运行中的 mihomo 控制接口。"
            return
        }
        await refreshLiveControllerData(socket: socket)
        await refreshLiveTraffic()
    }

    private func refreshLiveControllerData(socket: URL) async {
        if let snapshot = try? await liveService.proxies(socket: socket) {
            liveProxyGroups = snapshot.groups
            liveControllerTargets = snapshot.targetNames
        }
        await refreshLiveRulesAndProviders(socket: socket)
    }

    private func refreshLiveRulesAndProviders(socket: URL) async {
        if let rules = try? await liveService.rules(socket: socket) {
            liveControllerRules = rules
        }
        if let providers = try? await liveService.ruleProviders(socket: socket) {
            liveRuleProviders = providers
        }
    }

    private func resolveLiveSocket() async -> URL? {
        if let socket = workspace?.controlSocket {
            return socket
        }
        guard let discovered = await service.discover() else {
            return nil
        }
        workspace = discovered
        return discovered.controlSocket
    }

    private func markRuleDraftDirty() {
        ruleDraftIsValidated = false
        ruleDraftIsDirty = true
        ruleDraftIssues = []
        ruleDraftRenderedText = nil
        ruleDraftExportMessage = nil
    }

    private func isIPv4Literal(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, let number = Int(part) else { return false }
            return (0...255).contains(number)
        }
    }

    // MARK: - Protection

    func setProtectionEnabled(_ enabled: Bool) {
        guard protectionEnabled != enabled else { return }
        protectionEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.protectionEnabled)
        if enabled {
            appendProtectionEvent(.armed, "已启用实时守护")
            startProtectionMonitor()
        } else {
            stopProtectionMonitor()
            protectionPausedUntil = nil
            protectionState = .off
            protectionStatusText = "实时守护未启用"
            appendProtectionEvent(.disabled, "已停止实时守护")
        }
    }

    func setProtectionMode(_ mode: ProtectionMode) {
        protectionMode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKey.protectionMode)
        updateProtectionStatusForCurrentPolicy()
    }

    func setFallbackScanMinutes(_ minutes: Int) {
        fallbackScanMinutes = [0, 5, 15, 30].contains(minutes) ? minutes : 5
        defaults.set(fallbackScanMinutes, forKey: DefaultsKey.fallbackScanMinutes)
        if protectionEnabled {
            scheduleFallbackScan()
        }
    }

    func pauseProtection(for interval: TimeInterval) {
        guard protectionEnabled else { return }
        protectionPausedUntil = Date().addingTimeInterval(interval)
        protectionState = .paused
        protectionStatusText = "保护已暂停至 \(formattedTime(protectionPausedUntil))"
        changeMonitor?.stop()
        protectionFallbackTimer?.invalidate()
        protectionFallbackTimer = nil
        protectionPauseTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumeProtectionNow(reason: "暂停时间结束")
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        protectionPauseTimer = timer
        appendProtectionEvent(
            .paused,
            "暂停保护至 \(formattedTime(protectionPausedUntil))"
        )
    }

    func resumeProtectionNow(reason: String = "已手动恢复") {
        guard protectionEnabled else { return }
        protectionPauseTimer?.invalidate()
        protectionPauseTimer = nil
        protectionPausedUntil = nil
        startProtectionMonitor()
        appendProtectionEvent(.resumed, reason)
    }

    func scanProtectionNow() async {
        guard protectionEnabled else { return }
        await reconcileProtection(trigger: "手动检查")
    }

    private func startProtectionMonitor() {
        guard protectionEnabled else {
            protectionState = .off
            return
        }
        if isProtectionPaused {
            protectionState = .paused
            protectionStatusText = "保护已暂停至 \(formattedTime(protectionPausedUntil))"
            return
        }
        guard let workspace else {
            protectionState = .unavailable
            protectionStatusText = "等待 Clash Verge 配置目录"
            return
        }
        protectionState = .starting
        protectionStatusText = "正在启动文件事件监听…"

        if changeMonitor == nil {
            changeMonitor = DirectoryChangeMonitor { [weak self] paths in
                Task { @MainActor [weak self] in
                    self?.handleFileChanges(paths)
                }
            }
        }
        do {
            try changeMonitor?.start(directory: workspace.directory)
            protectionState = .active
            updateProtectionStatusForCurrentPolicy()
            lastProtectionCheck = Date()
            scheduleFallbackScan()
            Task { await reconcileProtection(trigger: "启用时基线检查") }
            if protectionEvents.first?.kind != .armed {
                appendProtectionEvent(.armed, "文件事件守护已启动")
            }
        } catch {
            protectionState = .attention
            protectionStatusText = "无法监听配置文件变化"
            errorMessage = error.localizedDescription
            appendProtectionEvent(.repairFailed, "启动事件监听失败：\(error.localizedDescription)")
        }
    }

    private func stopProtectionMonitor() {
        pendingProtectionScan?.cancel()
        pendingProtectionScan = nil
        changeMonitor?.stop()
        changeMonitor = nil
        protectionFallbackTimer?.invalidate()
        protectionFallbackTimer = nil
        protectionPauseTimer?.invalidate()
        protectionPauseTimer = nil
    }

    private func updateProtectionStatusForCurrentPolicy() {
        guard protectionEnabled, !isProtectionPaused else { return }
        if selectedProtectionOptionCount == 0 {
            protectionState = .attention
            protectionStatusText = "未选择任何自动保护项"
        } else if protectionMode == .notifyOnly {
            protectionState = .active
            protectionStatusText = "守护中 · 只监测不写入"
        } else {
            protectionState = .active
            protectionStatusText = "守护中 · \(selectedProtectionOptionCount) 个保护项"
        }
    }

    private func handleFileChanges(_ paths: [String]) {
        guard protectionEnabled, !isProtectionPaused else { return }
        let names: Set<String> = [
            "clash-verge.yaml",
            "dns_config.yaml",
            "verge.yaml",
            "profiles.yaml"
        ]
        let relevant = paths.contains { path in
            names.contains(URL(fileURLWithPath: path).lastPathComponent)
        }
        guard relevant else { return }
        scheduleProtectionScan(trigger: "检测到配置变化", delay: 0.9)
    }

    private func scheduleProtectionScan(trigger: String, delay: TimeInterval) {
        pendingProtectionScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reconcileProtection(trigger: trigger)
            }
        }
        pendingProtectionScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleFallbackScan() {
        protectionFallbackTimer?.invalidate()
        protectionFallbackTimer = nil
        guard protectionEnabled, fallbackScanMinutes > 0, !isProtectionPaused else {
            return
        }
        let interval = TimeInterval(fallbackScanMinutes * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reconcileProtection(trigger: "定期兜底检查")
            }
        }
        timer.tolerance = min(30, max(5, interval * 0.1))
        RunLoop.main.add(timer, forMode: .common)
        protectionFallbackTimer = timer
    }

    private func reconcileProtection(trigger: String) async {
        guard protectionEnabled, !isProtectionPaused else { return }
        guard !isProtectionReconciling else { return }
        guard !isBusy else {
            scheduleProtectionScan(trigger: trigger, delay: 2.5)
            return
        }
        isProtectionReconciling = true
        defer { isProtectionReconciling = false }

        do {
            let discovered = await service.discover() ?? workspace
            guard let discovered else {
                protectionState = .unavailable
                protectionStatusText = "等待 Clash Verge 配置目录"
                return
            }
            workspace = discovered
            if changeMonitor == nil {
                let monitor = DirectoryChangeMonitor { [weak self] paths in
                    Task { @MainActor [weak self] in
                        self?.handleFileChanges(paths)
                    }
                }
                try monitor.start(directory: discovered.directory)
                changeMonitor = monitor
            }

            let fingerprint = await Task.detached(priority: .utility) {
                Self.configurationFingerprint(workspace: discovered)
            }.value
            if trigger == "检测到配置变化",
               fingerprint == lastReconciledFingerprint {
                return
            }

            let result = try await Task.detached(priority: .utility) {
                let text = try String(
                    contentsOf: discovered.activeConfig,
                    encoding: .utf8
                )
                return try ConfigScanner.analyze(text: text)
            }.value
            analysis = result
            lastReconciledFingerprint = fingerprint
            lastProtectionCheck = Date()
            lastUpdated = Date()

            let evaluation = ProtectionPolicy.evaluate(
                analysis: result,
                selection: selection
            )
            if !evaluation.needsRepair, !evaluation.needsAttention {
                protectionState = .active
                protectionStatusText = protectionMode == .notifyOnly
                    ? "配置正常 · 仅监测"
                    : "配置正常 · \(selectedProtectionOptionCount) 个保护项"
                return
            }

            guard evaluation.needsRepair else {
                protectionState = .attention
                protectionStatusText = "发现 \(evaluation.unresolvedCriticalFindings.count) 项需人工处理的配置错误"
                appendProtectionEvent(
                    .change,
                    "\(trigger)：发现无法自动修复的配置错误"
                )
                await notifyIfAllowed(
                    title: "DNS Leak Guard 需要处理",
                    body: "检测到无法自动修复的 DNS 配置错误。"
                )
                return
            }

            let count = evaluation.repairableFindings.count
            if protectionMode == .notifyOnly {
                protectionState = .attention
                protectionStatusText = "发现 \(count) 项可修复风险，当前为仅监测"
                appendProtectionEvent(.change, "\(trigger)：发现 \(count) 项可修复风险")
                await notifyIfAllowed(
                    title: "检测到 DNS 配置变化",
                    body: "发现 \(count) 项可修复风险；实时守护当前处于仅监测模式。"
                )
                return
            }

            guard selectedProtectionOptionCount > 0 else {
                protectionState = .attention
                protectionStatusText = "发现风险，但没有勾选自动修复项"
                appendProtectionEvent(.change, "\(trigger)：没有勾选自动修复项")
                return
            }
            guard canAutoRepairNow() else {
                protectionState = .attention
                protectionStatusText = "自动写入暂时限流，仍持续监测"
                return
            }

            await performProtectionRepair(
                workspace: discovered,
                trigger: trigger,
                findingCount: count
            )
        } catch {
            protectionState = .attention
            protectionStatusText = "守护检查失败：\(error.localizedDescription)"
            appendProtectionEvent(.repairFailed, "\(trigger)失败：\(error.localizedDescription)")
        }
    }

    private func performProtectionRepair(
        workspace: WorkspaceInfo,
        trigger: String,
        findingCount: Int
    ) async {
        protectionState = .repairing
        protectionStatusText = "检测到变化，正在恢复 \(findingCount) 项保护…"
        appendProtectionEvent(.change, "\(trigger)：准备恢复 \(findingCount) 项保护")
        repairTimestamps.append(Date())

        do {
            let report = try await service.apply(
                workspace: workspace,
                selection: selection,
                proxyGroup: selectedProxyGroup,
                persistDNSOverride: persistDNSOverride
            )
            lastReport = report
            protectionRepairCount += 1
            self.workspace = await service.discover() ?? workspace
            try await refreshStatic()

            let currentAnalysis: ConfigAnalysis
            if let analysis {
                currentAnalysis = analysis
            } else {
                currentAnalysis = try ConfigScanner.analyze(
                    text: try String(contentsOf: workspace.activeConfig, encoding: .utf8)
                )
            }
            let reevaluation = ProtectionPolicy.evaluate(
                analysis: currentAnalysis,
                selection: selection
            )
            if reevaluation.needsRepair {
                protectionState = .attention
                protectionStatusText = "保护恢复后仍有 \(reevaluation.repairableFindings.count) 项风险"
                appendProtectionEvent(
                    .repairFailed,
                    "自动恢复后复检仍发现风险，请检查是否被上游持续覆盖"
                )
                if recentRepairCount(within: 30) >= 2 {
                    protectionAutoRepairBlockedUntil = Date().addingTimeInterval(600)
                    protectionStatusText = "多次恢复未保持，已暂停自动写入 10 分钟"
                }
                await notifyIfAllowed(
                    title: "DNS 自动恢复未保持",
                    body: "配置在恢复后再次出现风险，已进入保护性限流。"
                )
            } else {
                protectionState = reevaluation.needsAttention ? .attention : .active
                protectionStatusText = reevaluation.needsAttention
                    ? "DNS 保护已恢复，仍有需人工处理的错误"
                    : "配置已自动恢复并保持"
                appendProtectionEvent(
                    .repaired,
                    "已恢复 \(findingCount) 项保护"
                        + (report.reloadSucceeded ? "，Clash Verge 已重载" : "，等待 Clash Verge 重载")
                )
                await notifyIfAllowed(
                    title: "DNS 保护已自动恢复",
                    body: "检测到配置变化，已按您的勾选项恢复 DNS 防泄露设置。"
                )
            }
            scheduleProtectionScan(trigger: "修复后复检", delay: 2.0)
        } catch {
            protectionState = .attention
            protectionStatusText = "自动恢复失败：\(error.localizedDescription)"
            appendProtectionEvent(.repairFailed, "自动恢复失败：\(error.localizedDescription)")
            await notifyIfAllowed(
                title: "DNS 自动恢复失败",
                body: error.localizedDescription
            )
        }
    }

    private func canAutoRepairNow() -> Bool {
        let now = Date()
        if let blocked = protectionAutoRepairBlockedUntil, blocked > now {
            return false
        }
        repairTimestamps.removeAll { now.timeIntervalSince($0) > 3_600 }
        return repairTimestamps.count < 6
    }

    private func recentRepairCount(within seconds: TimeInterval) -> Int {
        let now = Date()
        return repairTimestamps.filter { now.timeIntervalSince($0) <= seconds }.count
    }

    private func appendProtectionEvent(
        _ kind: ProtectionEvent.Kind,
        _ message: String
    ) {
        protectionEvents.insert(
            ProtectionEvent(date: Date(), kind: kind, message: message),
            at: 0
        )
        if protectionEvents.count > 40 {
            protectionEvents.removeLast(protectionEvents.count - 40)
        }
    }

    // MARK: - System integration

    func setNotificationsEnabled(_ enabled: Bool) {
        if !enabled {
            notificationsEnabled = false
            defaults.set(false, forKey: DefaultsKey.notificationsEnabled)
            return
        }
        Task {
            let granted = await NotificationService.shared.requestAuthorization()
            notificationsAuthorized = granted
            notificationsEnabled = granted
            defaults.set(granted, forKey: DefaultsKey.notificationsEnabled)
            notificationStatusText = granted ? "已授权" : "已被系统拒绝"
            if !granted {
                errorMessage = "通知权限未授予；其余守护功能不受影响。"
            }
        }
    }

    func refreshNotificationAuthorization() async {
        let status = await NotificationService.shared.authorizationStatus()
        notificationsAuthorized = status == .authorized || status == .provisional
        switch status {
        case .authorized, .provisional:
            notificationStatusText = "已授权"
        case .denied:
            notificationStatusText = "已被系统拒绝"
        case .notDetermined:
            notificationStatusText = "未请求"
        @unknown default:
            notificationStatusText = "状态未知"
        }
        if !notificationsAuthorized, notificationsEnabled {
            notificationsEnabled = false
            defaults.set(false, forKey: DefaultsKey.notificationsEnabled)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            launchAtLoginStatusText = LaunchAtLogin.statusText
            if enabled, !launchAtLoginEnabled {
                errorMessage = "登录项已提交，但可能需要在“系统设置 → 通用 → 登录项”中批准。"
            }
        } catch {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            launchAtLoginStatusText = LaunchAtLogin.statusText
            errorMessage = "无法更改登录项：\(error.localizedDescription)"
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
        launchAtLoginStatusText = LaunchAtLogin.statusText
    }

    func setDashboardVisible(_ visible: Bool) {
        refreshMemoryFootprint()
        memoryTimer?.invalidate()
        memoryTimer = nil
        guard visible else { return }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMemoryFootprint()
            }
        }
        timer.tolerance = 4
        RunLoop.main.add(timer, forMode: .common)
        memoryTimer = timer
    }

    func refreshMemoryFootprint() {
        memoryMegabytes = ProcessFootprint.residentMegabytes()
    }

    func openBrowserLeaks() {
        if let url = URL(string: "https://browserleaks.com/dns") {
            NSWorkspace.shared.open(url)
        }
    }

    func revealActiveConfig() {
        guard let url = workspace?.activeConfig else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealConfigDirectory() {
        guard let url = workspace?.directory else { return }
        NSWorkspace.shared.open(url)
    }

    func revealBackups() {
        guard let backups = lastReport?.backups, !backups.isEmpty else {
            revealConfigDirectory()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(backups.map(\.backup))
    }

    func openClashVerge() {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Clash Verge.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Clash Verge.app")
        ]
        if let url = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "io.github.clash-verge-rev.clash-verge-rev"
        ) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    func openPrivacySettings(_ anchor: String) {
        SystemSettingsLink.openPrivacy(anchor)
    }

    func openLoginItemsSettings() {
        SystemSettingsLink.openLoginItems()
    }

    func openNotificationSettings() {
        SystemSettingsLink.openNotifications()
    }

    // MARK: - Helpers

    private func refreshStatic() async throws {
        guard let workspace else {
            throw SimpleError("Clash Verge 配置目录不可用。")
        }
        let result = try await Task.detached(priority: .userInitiated) {
            let text = try String(
                contentsOf: workspace.activeConfig,
                encoding: .utf8
            )
            return try ConfigScanner.analyze(text: text)
        }.value
        analysis = result
        if selectedProxyGroup == nil
            || result.proxyGroups.contains(where: { $0.name == selectedProxyGroup }) == false {
            setSelectedProxyGroup(result.suggestedProxyGroup)
        }
    }

    private func refreshRuntimeAndHealth(
        workspace: WorkspaceInfo
    ) async {
        let service = service
        let runtimeTask = Task {
            await service.runtimeStatus(workspace: workspace)
        }
        let healthTask = Task.detached(priority: .utility) {
            service.health(workspace: workspace)
        }
        runtimeStatus = await runtimeTask.value
        health = await healthTask.value
    }

    private func runSelectedProvidersInternal() async {
        let providers = DNSLeakProviderID.allCases.filter {
            selectedProviders.contains($0)
        }
        guard !providers.isEmpty else {
            providerResults = []
            liveResult = nil
            providerProgressText = "未选择任何测漏站点"
            return
        }

        providerResults = []
        providerProgressText = "正在检测 \(providers.count) 个站点…"
        var collected: [DNSLeakProviderResult] = []

        await withTaskGroup(of: DNSLeakProviderResult.self) { group in
            for provider in providers {
                group.addTask {
                    await DNSLeakProviders.run(provider: provider)
                }
            }
            for await result in group {
                collected.append(result)
                collected.sort {
                    Self.providerSortIndex($0.provider)
                        < Self.providerSortIndex($1.provider)
                }
                providerResults = collected
                providerProgressText =
                    "已完成 \(collected.count) / \(providers.count) 个站点"
            }
        }

        updateLiveResultFromProviders()
        let nativeCount = collected.filter {
            $0.provider.isNativeResult
        }.count
        providerProgressText =
            "完成 \(collected.count) 个站点 · \(nativeCount) 个原生探测"
    }

    private func scheduleDeepLinkAction(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        deepLinkActionTask?.cancel()
        deepLinkActionTask = Task { @MainActor in
            await waitForStartupForDeepLink()
            guard !Task.isCancelled else { return }
            guard !isBusy, protectionState != .repairing else {
                errorMessage = "深链请求未执行：当前已有检测或修复任务正在运行。"
                return
            }
            await operation()
        }
    }

    private func waitForStartupForDeepLink() async {
        let deadline = Date().addingTimeInterval(20)
        while activity == .starting, Date() < deadline {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func runDetectionAfterStartup() async {
        await runDetection()
    }

    private func runOnlineTestAfterStartup() async {
        await runLiveTestOnly()
    }

    private func dashboardSection(
        for section: DNSLeakGuardSection
    ) -> DashboardSection {
        switch section {
        case .overview: .overview
        case .findings: .findings
        case .liveTests: .liveTests
        case .traffic: .traffic
        case .repair: .repair
        case .routing: .routing
        case .protection: .protection
        case .permissions: .permissions
        }
    }

    private func updateLiveResultFromProviders() {
        let native = providerResults.filter {
            $0.provider.isNativeResult && !$0.observations.isEmpty
        }
        guard !native.isEmpty else {
            liveResult = nil
            return
        }
        var byIP: [String: DNSObservation] = [:]
        for observation in native.flatMap(\.observations) {
            if let existing = byIP[observation.ip] {
                if existing.isp.isEmpty, !observation.isp.isEmpty {
                    byIP[observation.ip] = observation
                }
            } else {
                byIP[observation.ip] = observation
            }
        }
        let observations = byIP.values.sorted {
            $0.ip.localizedStandardCompare($1.ip) == .orderedAscending
        }
        let multiple = native.contains {
            $0.outcome == .multiplePaths
        }
        let isps = Set(observations.map(\.isp).filter { !$0.isEmpty })
        let locations = Set(observations.map(\.location).filter { !$0.isEmpty })
        let message: String
        if multiple {
            message = "\(native.count) 个站点给出原生结果，合并发现 "
                + "\(observations.count) 个解析器、\(isps.count) 个 ISP、"
                + "\(locations.count) 个地区；存在多解析器路径。"
        } else {
            message = "\(native.count) 个站点给出原生结果，合并发现 "
                + "\(observations.count) 个解析器，均归属 "
                + "\(isps.first ?? "未知 ISP") / "
                + "\(locations.first ?? "未知地区")。"
        }
        liveResult = LiveDNSTestResult(
            observations: observations,
            queriesSucceeded: native.map(\.queriesSucceeded).reduce(0, +),
            queriesAttempted: native.map(\.queriesAttempted).reduce(0, +),
            outcome: multiple ? .multipleResolverPaths : .singleResolverPath,
            message: message
        )
    }

    private func persistProviderSelection() {
        defaults.set(
            DNSLeakProviderID.allCases
                .filter(selectedProviders.contains)
                .map(\.rawValue),
            forKey: DefaultsKey.selectedProviders
        )
    }

    private static func providerSortIndex(
        _ provider: DNSLeakProviderID
    ) -> Int {
        DNSLeakProviderID.allCases.firstIndex(of: provider) ?? 0
    }

    nonisolated private static func configurationFingerprint(
        workspace: WorkspaceInfo
    ) -> String {
        let urls = [
            workspace.activeConfig,
            workspace.dnsOverride,
            workspace.vergeSettings,
            workspace.profilesFile
        ].compactMap { $0 }
        let keys = urls.map { url -> String in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path
            )
            let modified = (attributes?[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? 0
            let size = attributes?[.size] as? NSNumber ?? 0
            return "\(url.lastPathComponent):\(modified):\(size.intValue)"
        }
        return keys.joined(separator: "|")
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        activity = .idle
        progressText = "操作未完成"
    }

    private func notifyIfAllowed(title: String, body: String) async {
        guard notificationsEnabled, notificationsAuthorized else { return }
        let now = Date()
        guard now.timeIntervalSince(lastNotificationAt) > 45 else { return }
        lastNotificationAt = now
        await NotificationService.shared.send(title: title, body: body)
    }

    private func defaultsKey(for option: FixOptionType) -> String {
        switch option {
        case .removePlaintextDNS: DefaultsKey.removePlaintextDNS
        case .bindDNSToProxy: DefaultsKey.bindDNSToProxy
        case .enableMihomoDNS: DefaultsKey.enableMihomoDNS
        case .fixDNSKeyTypos: DefaultsKey.fixDNSKeyTypos
        case .addNoResolve: DefaultsKey.addNoResolve
        }
    }

    private func formattedTime(_ date: Date?) -> String {
        guard let date else { return "未知时间" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct SimpleError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
