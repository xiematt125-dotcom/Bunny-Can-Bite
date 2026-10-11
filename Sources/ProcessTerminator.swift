import Darwin
import Foundation

/// Immutable targets captured before the confirmation sheet opens.
struct TerminationRequest: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let processes: [ProcessMemory]
    let isGroup: Bool

    init(name: String, processes: [ProcessMemory], isGroup: Bool) {
        id = UUID()
        self.name = name
        self.processes = processes
        self.isGroup = isGroup
    }
}

enum TerminationOutcome: String, Codable, CaseIterable, Sendable {
    case terminated, alreadyExited, identityChanged, permissionDenied, protected, failed, stillRunning
}

struct TerminationResult: Identifiable, Codable, Sendable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let outcome: TerminationOutcome
    let message: String
}

struct TerminationReport: Identifiable, Codable, Sendable {
    let id: UUID
    let requestID: UUID
    let name: String
    let results: [TerminationResult]

    init(requestID: UUID, name: String, results: [TerminationResult]) {
        id = UUID()
        self.requestID = requestID
        self.name = name
        self.results = results
    }

    var title: String {
        if results.isEmpty { return "没有可处理的进程" }
        if results.allSatisfy({ $0.outcome == .terminated || $0.outcome == .alreadyExited }) {
            return "所选进程已退出"
        }
        if results.contains(where: { $0.outcome == .terminated }) { return "部分进程已退出" }
        return "强制退出结果"
    }

    var message: String {
        guard !results.isEmpty else { return "确认时的进程列表为空，请刷新后重试。" }
        let terminated = results.filter { $0.outcome == .terminated }.count
        let exited = results.filter { $0.outcome == .alreadyExited }.count
        let other = results.count - terminated - exited
        return "已强制退出 \(terminated) 个，操作前已退出 \(exited) 个，其他结果 \(other) 个。系统可能自动重启部分进程；实际内存变化以刷新后的面板为准。"
    }
}

/// Run on the store's serial background queue. No shell, sudo, name matching,
/// process-group signalling, or discovery of extra targets during termination.
struct ProcessTerminator: Sendable {
    struct State: Sendable {
        let identity: ProcessIdentity
        let isZombie: Bool
        let name: String
        let executablePath: String
        let isSystem: Bool
    }

    enum Probe: Sendable {
        case running(State)
        case failure(Int32)
    }

    struct Environment: Sendable {
        let read: @Sendable (Int32) -> Probe
        let signal: @Sendable (ProcessMemory) -> Int32
        let wait: @Sendable () -> Void

        static let live = Environment(read: { pid in
            var state = CMProcessState()
            let error = cm_read_process_state(pid, &state)
            guard error == 0 else { return .failure(error) }
            return .running(State(identity: ProcessIdentity(seconds: state.start_seconds, microseconds: state.start_microseconds),
                                  isZombie: state.is_zombie != 0, name: fixedCString(state.name),
                                  executablePath: fixedCString(state.path), isSystem: state.is_system != 0))
        }, signal: { process in
            guard let identity = process.identity else { return CM_TERMINATION_IDENTITY_CHANGED }
            return cm_force_quit(process.pid, identity.seconds, identity.microseconds)
        }, wait: { Thread.sleep(forTimeInterval: 0.05) })
    }

    private let environment: Environment

    init(environment: Environment = .live) {
        self.environment = environment
    }

    static func blockedReason(for process: ProcessMemory) -> String? {
        if process.pid <= 1 { return "系统核心进程受保护，无法在这里强制退出。" }
        if process.pid == getpid() { return "内存面板自身受保护，请通过应用菜单正常退出。" }
        if process.isSystem == true { return "系统核心进程受保护，无法在这里强制退出。" }
        if isCritical(name: process.name, path: process.executablePath) {
            return "此进程维持系统或登录会话，强制退出可能导致注销，已保护。"
        }
        guard let identity = process.identity, identity.seconds > 0, identity.microseconds < 1_000_000 else {
            return "无法确认此进程的启动身份，请刷新后重试。"
        }
        return nil
    }

    func terminate(_ request: TerminationRequest) -> TerminationReport {
        var seen: [Int32: ProcessMemory] = [:]
        var conflicts: Set<Int32> = []
        let targets = request.processes.filter { process in
            if let previous = seen[process.pid] {
                if previous.identity != process.identity { conflicts.insert(process.pid) }
                return false
            }
            seen[process.pid] = process
            return true
        }
        var results: [Int32: TerminationResult] = [:]
        var pending: [ProcessMemory] = []
        for process in targets {
            if conflicts.contains(process.pid) {
                results[process.pid] = result(process, .identityChanged, "确认列表包含同一 PID 的不同身份，已跳过，请刷新。")
            } else if let reason = Self.blockedReason(for: process) {
                results[process.pid] = result(process, .protected, reason)
            } else if let failure = preflight(process) {
                results[process.pid] = failure
            } else {
                // The C boundary repeats identity and critical-process checks
                // immediately before SIGKILL to reject stale confirmation data.
                let error = environment.signal(process)
                if error == 0 { pending.append(process) }
                else { results[process.pid] = failureResult(process, error: error) }
            }
        }

        // One bounded verification window for the entire confirmed group, avoiding
        // a separate timeout for every child in a large application.
        for attempt in 0..<21 {
            pending = pending.filter { process in
                switch environment.read(process.pid) {
                case .failure(ESRCH):
                    results[process.pid] = result(process, .terminated, "已确认所选进程退出。")
                case .failure(let error):
                    results[process.pid] = result(process, .failed, "已发送退出信号，但无法确认结果（错误 \(error)）；请刷新查看。")
                case .running(let state):
                    if state.identity != process.identity || state.isZombie {
                        results[process.pid] = result(process, .terminated, "已确认所选进程退出。")
                    } else {
                        return true
                    }
                }
                return false
            }
            if pending.isEmpty { break }
            if attempt < 20 { environment.wait() }
        }
        for process in pending {
            results[process.pid] = result(process, .stillRunning, "已发送退出信号，但进程仍在运行；请稍后刷新查看。")
        }
        return TerminationReport(requestID: request.id, name: request.name, results: targets.compactMap { results[$0.pid] })
    }

    private func preflight(_ process: ProcessMemory) -> TerminationResult? {
        switch environment.read(process.pid) {
        case .failure(let error): return failureResult(process, error: error)
        case .running(let state):
            guard state.identity == process.identity else {
                return result(process, .identityChanged, "进程身份已变化，已跳过，请刷新后重新选择。")
            }
            if state.isSystem || Self.isCritical(name: state.name, path: state.executablePath) {
                return result(process, .protected, "系统关键进程受保护，无法在这里强制退出。")
            }
            if state.isZombie { return result(process, .alreadyExited, "所选进程已经退出。") }
            return nil
        }
    }

    private func failureResult(_ process: ProcessMemory, error: Int32) -> TerminationResult {
        switch error {
        case ESRCH: return result(process, .alreadyExited, "所选进程已经退出。")
        case EPERM, EACCES: return result(process, .permissionDenied, "macOS 拒绝操作：当前用户没有权限或该进程受系统保护。")
        case CM_TERMINATION_IDENTITY_CHANGED: return result(process, .identityChanged, "进程身份已变化，已跳过，请刷新后重新选择。")
        case CM_TERMINATION_PROTECTED: return result(process, .protected, "系统或面板自身进程受保护，已跳过。")
        default: return result(process, .failed, "无法完成操作（错误 \(error)），请刷新后重试。")
        }
    }

    private func result(_ process: ProcessMemory, _ outcome: TerminationOutcome, _ message: String) -> TerminationResult {
        TerminationResult(pid: process.pid, name: process.name, outcome: outcome, message: message)
    }

    private static func isCritical(name: String, path: String) -> Bool {
        let protected = ["kernel_task", "launchd", "loginwindow", "windowserver"]
        return protected.contains(name.lowercased()) || protected.contains(URL(fileURLWithPath: path).lastPathComponent.lowercased())
    }

    private static func fixedCString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
}
