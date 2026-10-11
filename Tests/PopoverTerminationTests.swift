import Darwin
import Foundation

@main
struct PopoverTerminationTests {
    @MainActor
    static func main() {
        testImmutableTargetsAndCancellation()
        testSubmissionAndRequestIsolation()
        testCloseAndReopen()
        testProtectedTargets()
        print("PASS: popover immutable targets, cancel, single submission, report isolation, close/reopen and protected targets")
    }

    private static func process(_ pid: Int32 = 45_001, identity: UInt64 = 100, isSystem: Bool = false) -> ProcessMemory {
        .init(pid: pid, parentPID: 1, name: "Fixture \(pid)", executablePath: "/tmp/MemoryGlassFixture",
              bytes: 1_024, metric: "footprint", identity: .init(seconds: identity, microseconds: 1), isSystem: isSystem)
    }

    private static func request(_ pid: Int32 = 45_001) -> TerminationRequest {
        .init(name: "Fixture App", processes: [process(pid)], isGroup: true)
    }

    private static func report(_ request: TerminationRequest, outcome: TerminationOutcome = .terminated) -> TerminationReport {
        .init(requestID: request.id, name: request.name,
              results: request.processes.map { .init(pid: $0.pid, name: $0.name, outcome: outcome, message: "Fixture result") })
    }

    @MainActor
    private static func testImmutableTargetsAndCancellation() {
        let state = PopoverTerminationState()
        var sampledProcesses = [process()]
        let original = TerminationRequest(name: "Fixture App", processes: sampledProcesses, isGroup: true)
        precondition(state.begin(original, isBusy: false))
        sampledProcesses = [process(45_002, identity: 200)]
        precondition(state.request?.processes.first?.pid == 45_001)
        precondition(state.request?.processes.first?.identity?.seconds == 100)
        precondition(!state.begin(request(45_003), isBusy: false))
        state.dismiss()
        precondition(state.request == nil)
        precondition(state.submit(isBusy: false) == nil, "Cancel must not produce a request to execute")
        precondition(!state.begin(original, isBusy: true))
        precondition(state.begin(original, isBusy: false))
        precondition(state.submit(isBusy: true) == nil)
        state.dismiss()
        precondition(state.request == nil, "An unsubmitted request can be cancelled while another operation is busy")
    }

    @MainActor
    private static func testSubmissionAndRequestIsolation() {
        let state = PopoverTerminationState()
        let own = request()
        let unrelated = request(45_002)
        precondition(state.begin(own, isBusy: false))
        state.receive(report(own))
        precondition(state.report == nil, "Reports cannot bypass confirmation")
        state.receive(report(unrelated))
        precondition(state.report == nil)
        precondition(state.submit(isBusy: false)?.id == own.id)
        precondition(state.submit(isBusy: false) == nil, "A request can only be submitted once")
        state.receive(report(unrelated))
        precondition(state.report == nil, "A dashboard report must never appear in this flow")
        state.dismiss()
        precondition(state.request?.id == own.id, "In-flight targets remain available after dismissal attempts")
        let completion = report(own, outcome: .stillRunning)
        state.receive(completion)
        precondition(state.report?.id == completion.id)
        state.receive(nil)
        state.receive(report(unrelated))
        precondition(state.report?.id == completion.id, "Another operation must not clear or replace the completed result")
        precondition(state.submit(isBusy: false) == nil, "A completed request cannot be submitted again")
        precondition(PopoverTerminationPresentation.resultLabel(.stillRunning) == "未确认退出")
        precondition(PopoverTerminationPresentation.resultLabel(.failed) == "需检查")
        state.dismiss()
        precondition(state.request == nil && state.report == nil && !state.hasSubmitted)
    }

    @MainActor
    private static func testCloseAndReopen() {
        let state = PopoverTerminationState()
        let own = request()
        precondition(state.begin(own, isBusy: false))
        state.popoverDidClose()
        precondition(state.request == nil, "Closing the popover cancels an unsubmitted confirmation")
        precondition(state.begin(own, isBusy: false))
        precondition(state.submit(isBusy: false)?.id == own.id)
        state.popoverDidClose()
        precondition(state.request?.id == own.id && state.hasSubmitted)
        state.receive(report(own))
        state.popoverDidClose()
        precondition(state.report?.requestID == own.id, "Completion survives closure until the user dismisses it")
    }

    @MainActor
    private static func testProtectedTargets() {
        let selfProcess = process(getpid())
        let systemProcess = process(45_003, isSystem: true)
        let protected = AppMemory(id: "protected", name: "Protected", bundlePath: nil, isApplication: true,
                                  processes: [selfProcess, systemProcess])
        precondition(PopoverTerminationPresentation.blockedReason(for: protected) != nil)
        let state = PopoverTerminationState()
        precondition(!state.begin(.init(name: protected.name, processes: protected.processes, isGroup: true), isBusy: false))
        let empty = AppMemory(id: "empty", name: "Empty", bundlePath: nil, isApplication: true, processes: [])
        precondition(PopoverTerminationPresentation.blockedReason(for: empty) != nil)
        let mixed = AppMemory(id: "mixed", name: "Mixed", bundlePath: nil, isApplication: true,
                              processes: [selfProcess, process()])
        precondition(PopoverTerminationPresentation.blockedReason(for: mixed) == nil)
        precondition(state.begin(.init(name: mixed.name, processes: mixed.processes, isGroup: true), isBusy: false))
        precondition(state.request?.processes.count == 2, "Protected entries stay visible in the confirmation snapshot")
    }
}
