import Darwin
import Foundation
import os

private final class FakeProcesses: Sendable {
    struct State {
        var probes: [Int32: [ProcessTerminator.Probe]] = [:]
        var signals: [Int32] = []
        var signalErrors: [Int32: Int32] = [:]
        var waits = 0
    }
    let state = OSAllocatedUnfairLock(initialState: State())
    var environment: ProcessTerminator.Environment {
        .init(read: { [self] pid in
            state.withLock { value in
                guard var sequence = value.probes[pid], !sequence.isEmpty else { return .failure(ESRCH) }
                let next = sequence[0]
                if sequence.count > 1 { sequence.removeFirst(); value.probes[pid] = sequence }
                return next
            }
        }, signal: { [self] process in
            state.withLock { value in
                value.signals.append(process.pid)
                return value.signalErrors[process.pid] ?? 0
            }
        }, wait: { [self] in state.withLock { $0.waits += 1 } })
    }
}

@main
struct TerminatorTests {
    static let identity = ProcessIdentity(seconds: 100, microseconds: 200)

    static func main() throws {
        testProtection()
        testPreSignalFailures()
        testSignalFailures()
        testVerification()
        testGroupIsolationAndDedupe()
        try testReportsAndCodable()
        try testOwnedChildIntegration()
        print("PASS: force-quit protection, stale identity, errors, verified outcomes, group isolation, dedupe, 10k targets, serialization, owned-child integration")
    }

    static func process(_ pid: Int32 = 91_234, name: String = "测试程序 🐇", identity: ProcessIdentity? = identity) -> ProcessMemory {
        ProcessMemory(pid: pid, parentPID: 1, name: name, executablePath: "/tmp/Test.app/Contents/MacOS/Test", bytes: 1_048_576, metric: "footprint", identity: identity)
    }

    static func running(_ value: ProcessIdentity = identity, zombie: Bool = false, name: String = "Test", system: Bool = false) -> ProcessTerminator.Probe {
        .running(.init(identity: value, isZombie: zombie, name: name, executablePath: "/tmp/Test", isSystem: system))
    }

    static func request(_ processes: [ProcessMemory]) -> TerminationRequest {
        .init(name: "测试程序 🐇", processes: processes, isGroup: processes.count > 1)
    }

    private static func result(probes: [ProcessTerminator.Probe], signal: Int32 = 0) -> (TerminationResult, FakeProcesses) {
        let fake = FakeProcesses()
        let target = process()
        fake.state.withLock { $0.probes[target.pid] = probes; $0.signalErrors[target.pid] = signal }
        let report = ProcessTerminator(environment: fake.environment).terminate(request([target]))
        precondition(report.results.count == 1)
        return (report.results[0], fake)
    }

    static func testProtection() {
        let targets = [process(-9), process(0), process(1), process(getpid()), process(name: "loginwindow"),
                       process(name: "WindowServer"), process(name: "kernel_task"), process(name: "launchd"),
                       process(identity: nil)]
        for target in targets {
            precondition(ProcessTerminator.blockedReason(for: target) != nil)
            let fake = FakeProcesses()
            let report = ProcessTerminator(environment: fake.environment).terminate(request([target]))
            precondition(report.results[0].outcome == .protected)
            precondition(fake.state.withLock { $0.signals.isEmpty })
        }
        let pathProtected = ProcessMemory(pid: 555, parentPID: 1, name: "name unavailable", executablePath: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow", bytes: 0, metric: "unavailable", identity: identity)
        precondition(ProcessTerminator.blockedReason(for: pathProtected) != nil)
        let flagProtected = ProcessMemory(pid: 556, parentPID: 1, name: "system service", executablePath: "/unknown/system", bytes: 0, metric: "unavailable", identity: identity, isSystem: true)
        precondition(ProcessTerminator.blockedReason(for: flagProtected) != nil)
        precondition(ProcessTerminator.blockedReason(for: process()) == nil)
    }

    static func testPreSignalFailures() {
        for (probe, expected): (ProcessTerminator.Probe, TerminationOutcome) in [
            (.failure(ESRCH), .alreadyExited), (.failure(EPERM), .permissionDenied),
            (.failure(EACCES), .permissionDenied), (.failure(EIO), .failed),
            (running(.init(seconds: 100, microseconds: 201)), .identityChanged),
            (running(zombie: true), .alreadyExited), (running(name: "WindowServer"), .protected),
            (running(system: true), .protected)
        ] {
            let (outcome, fake) = result(probes: [probe])
            precondition(outcome.outcome == expected, "unexpected pre-signal outcome: \(outcome)")
            precondition(fake.state.withLock { $0.signals.isEmpty })
        }
    }

    static func testSignalFailures() {
        for (error, expected): (Int32, TerminationOutcome) in [
            (ESRCH, .alreadyExited), (EPERM, .permissionDenied), (EACCES, .permissionDenied),
            (EIO, .failed), (CM_TERMINATION_IDENTITY_CHANGED, .identityChanged),
            (CM_TERMINATION_PROTECTED, .protected)
        ] {
            let (outcome, fake) = result(probes: [running()], signal: error)
            precondition(outcome.outcome == expected)
            precondition(fake.state.withLock { $0.signals == [process().pid] })
            precondition(fake.state.withLock { $0.waits == 0 })
        }
    }

    static func testVerification() {
        for (probes, expected): ([ProcessTerminator.Probe], TerminationOutcome) in [
            ([running(), .failure(ESRCH)], .terminated),
            ([running(), running(zombie: true)], .terminated),
            ([running(), running(.init(seconds: 101, microseconds: 0))], .terminated),
            ([running(), .failure(EPERM)], .failed),
            ([running(), .failure(EIO)], .failed),
            ([running()], .stillRunning)
        ] {
            let (outcome, fake) = result(probes: probes)
            precondition(outcome.outcome == expected)
            precondition(fake.state.withLock { $0.signals.count == 1 })
            if expected == .stillRunning { precondition(fake.state.withLock { $0.waits > 0 && $0.waits <= 20 }) }
        }
    }

    static func testGroupIsolationAndDedupe() {
        let fake = FakeProcesses()
        let original = process()
        let denied = process(91_235)
        fake.state.withLock {
            $0.probes[original.pid] = [running(), .failure(ESRCH)]
            $0.probes[denied.pid] = [running()]
            $0.signalErrors[denied.pid] = EPERM
        }
        let report = ProcessTerminator(environment: fake.environment).terminate(request([original, original, denied]))
        precondition(report.results.map(\.pid) == [original.pid, denied.pid])
        precondition(report.results.map(\.outcome) == [.terminated, .permissionDenied])
        precondition(fake.state.withLock { $0.signals == [original.pid, denied.pid] })
        let empty = ProcessTerminator(environment: fake.environment).terminate(request([]))
        precondition(empty.results.isEmpty && !empty.message.isEmpty)
        let largeFake = FakeProcesses()
        let large = ProcessTerminator(environment: largeFake.environment).terminate(request((100_000..<110_000).map { process(Int32($0)) }))
        precondition(large.results.count == 10_000 && large.results.allSatisfy { $0.outcome == .alreadyExited })
        precondition(largeFake.state.withLock { $0.signals.isEmpty })
        // Conflicting identities for a duplicate PID must not choose an arbitrary target.
        let conflictFake = FakeProcesses()
        let conflict = ProcessTerminator(environment: conflictFake.environment).terminate(request([original, process(original.pid, identity: .init(seconds: 999, microseconds: 0))]))
        precondition(conflict.results.count == 1 && conflict.results[0].outcome == .identityChanged)
        precondition(conflictFake.state.withLock { $0.signals.isEmpty })
    }

    static func testReportsAndCodable() throws {
        for outcome in TerminationOutcome.allCases {
            let report = TerminationReport(name: "测试程序 🐇", results: [.init(pid: 42, name: "测试程序 🐇", outcome: outcome, message: "结果")])
            precondition(!report.title.isEmpty && !report.message.isEmpty)
            let decoded = try JSONDecoder().decode(TerminationReport.self, from: JSONEncoder().encode(report))
            precondition(decoded.results[0].outcome == outcome && decoded.results[0].id == 42)
            precondition(decoded.id == report.id)
        }
        let original = request([process()])
        let decoded = try JSONDecoder().decode(TerminationRequest.self, from: JSONEncoder().encode(original))
        precondition(decoded.id == original.id && decoded.processes[0].identity == identity)
        let legacy = "{\"pid\":9,\"parentPID\":1,\"name\":\"old\",\"executablePath\":\"/tmp/old\",\"bytes\":1,\"metric\":\"rss\"}".data(using: .utf8)!
        let legacyProcess = try JSONDecoder().decode(ProcessMemory.self, from: legacy)
        precondition(legacyProcess.identity == nil)
    }

    static func testOwnedChildIntegration() throws {
        var invalid = CMProcessState()
        precondition(cm_read_process_state(-1, &invalid) == EINVAL)
        precondition(cm_force_quit(0, 100, 200) == CM_TERMINATION_PROTECTED)
        precondition(cm_force_quit(1, 100, 200) == CM_TERMINATION_PROTECTED)
        precondition(cm_force_quit(getpid(), 100, 200) == CM_TERMINATION_PROTECTED)
        // This is the only real signal target: a disposable child created by this test.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
        var state = CMProcessState()
        precondition(cm_read_process_state(child.processIdentifier, &state) == 0)
        let start = ProcessIdentity(seconds: state.start_seconds, microseconds: state.start_microseconds)
        precondition(start.seconds > 0)
        precondition(cm_force_quit(child.processIdentifier, start.seconds + 1, start.microseconds) == CM_TERMINATION_IDENTITY_CHANGED)
        precondition(child.isRunning)
        let target = process(child.processIdentifier, name: "Owned test child", identity: start)
        let report = ProcessTerminator().terminate(request([target]))
        precondition(report.results[0].outcome == .terminated)
        child.waitUntilExit()
        precondition(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL)
        let repeated = ProcessTerminator().terminate(request([target]))
        precondition(repeated.results[0].outcome == .alreadyExited)
    }
}
