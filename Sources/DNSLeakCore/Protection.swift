import CoreServices
import Darwin
import Foundation

public enum ProtectionMode: String, CaseIterable, Identifiable, Sendable {
    case notifyOnly
    case autoRepair

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notifyOnly: "仅监测"
        case .autoRepair: "自动修复"
        }
    }

    public var detail: String {
        switch self {
        case .notifyOnly:
            "配置变化后立即重新扫描，只提示风险，不写入任何文件。"
        case .autoRepair:
            "配置变化后重新扫描，并仅针对已勾选的保护项自动恢复。"
        }
    }
}

public struct ProtectionEvaluation: Sendable {
    public let repairableFindings: [Finding]
    public let unresolvedCriticalFindings: [Finding]

    public init(repairableFindings: [Finding], unresolvedCriticalFindings: [Finding]) {
        self.repairableFindings = repairableFindings
        self.unresolvedCriticalFindings = unresolvedCriticalFindings
    }

    public var needsRepair: Bool {
        !repairableFindings.isEmpty
    }

    public var needsAttention: Bool {
        !unresolvedCriticalFindings.isEmpty
    }

    public var highestRisk: RiskLevel {
        (repairableFindings + unresolvedCriticalFindings).map(\.severity).max() ?? .info
    }
}

public enum ProtectionPolicy {
    public static func evaluate(
        analysis: ConfigAnalysis,
        selection: FixSelection
    ) -> ProtectionEvaluation {
        let repairable = analysis.findings.filter { finding in
            guard let fix = finding.fix else { return false }
            return selection.isEnabled(fix)
        }
        let unresolved = analysis.findings.filter {
            $0.category == .configError && $0.severity >= .high && $0.fix == nil
        }
        return ProtectionEvaluation(
            repairableFindings: repairable,
            unresolvedCriticalFindings: unresolved
        )
    }
}

/// A deliberately small FSEvents wrapper. It watches one directory and delivers
/// coalesced paths on a utility queue; semantic filtering and debouncing belong
/// to the caller.
public final class DirectoryChangeMonitor: @unchecked Sendable {
    public typealias Handler = @Sendable ([String]) -> Void

    private let queue = DispatchQueue(
        label: "io.dnsleakguard.fsevents",
        qos: .utility
    )
    private let handler: Handler
    private var stream: FSEventStreamRef?

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start(
        directory: URL,
        latency: TimeInterval = 0.45
    ) throws {
        stop()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )
        let paths = [directory.path] as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            dnsLeakGuardFSEventsCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            throw DirectoryChangeMonitorError.creationFailed
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw DirectoryChangeMonitorError.startFailed
        }
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func receive(paths: [String]) {
        guard !paths.isEmpty else { return }
        handler(paths)
    }
}

public enum DirectoryChangeMonitorError: LocalizedError {
    case creationFailed
    case startFailed

    public var errorDescription: String? {
        switch self {
        case .creationFailed: "无法创建配置文件事件监听器。"
        case .startFailed: "无法启动配置文件事件监听器。"
        }
    }
}

private func dnsLeakGuardFSEventsCallback(
    _ stream: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let monitor = Unmanaged<DirectoryChangeMonitor>
        .fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
    monitor.receive(paths: paths)
}

public enum ProcessFootprint {
    public static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size
                / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    public static func residentMegabytes() -> Double {
        Double(residentBytes()) / 1_048_576
    }
}
