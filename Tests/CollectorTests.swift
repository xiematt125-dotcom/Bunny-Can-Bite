import Foundation

@main
struct CollectorTests {
    static func main() throws {
        if CommandLine.arguments.contains("--json") {
            let snapshot = try MemoryCollector().collect()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            print(String(data: try encoder.encode(snapshot), encoding: .utf8)!)
            return
        }
        testMath()
        testGrouping()
        let collector = MemoryCollector()
        var durations: [Double] = []
        for _ in 0..<5 {
            let live = try collector.collect()
            precondition(live.totalBytes > 0 && live.usedBytes <= live.totalBytes)
            precondition(live.processCount > 20)
            precondition(live.groups.reduce(0) { $0 + $1.processes.count } == live.processCount)
            precondition(live.groups.flatMap(\.processes).contains { $0.pid == ProcessInfo.processInfo.processIdentifier && $0.metric == "footprint" && $0.bytes > 0 })
            let ownProcess = live.groups.flatMap(\.processes).first { $0.pid == ProcessInfo.processInfo.processIdentifier }!
            precondition(ownProcess.identity?.seconds ?? 0 > 0)
            precondition(ownProcess.identity?.microseconds ?? 1_000_000 < 1_000_000)
            precondition(ownProcess.isSystem == false)
            precondition(Set(live.groups.flatMap(\.processes).map(\.pid)).count == live.processCount)
            precondition(live.unavailableCount == live.groups.flatMap(\.processes).filter { $0.metric == "unavailable" }.count)
            precondition(live.rssCount == live.groups.flatMap(\.processes).filter { $0.metric == "rss" }.count)
            durations.append(live.collectionDurationMS)
        }
        print("PASS: VM counter math, pressure unknown, grouping/ancestry, unavailable retention, 5 live snapshots")
        print("Collection ms: \(durations.map { String(format: "%.1f", $0) }.joined(separator: ", "))")
    }

    static func testMath() {
        var vm = CMGlobalMemory()
        vm.total_bytes = 16_384 * 1_000
        vm.page_size = 16_384
        vm.internal_pages = 500
        vm.purgeable_pages = 100
        vm.wired_pages = 80
        vm.compressed_pages = 40
        vm.external_pages = 120
        vm.free_pages = 260
        let totals = MemoryCollector.memoryTotals(vm)
        precondition(totals.app == 400 * 16_384)
        precondition(totals.used == 520 * 16_384)
        precondition(totals.cached == 220 * 16_384)
        precondition(totals.free == 260 * 16_384)
        // Reclaimable count can transiently exceed internal count. No underflow.
        vm.purgeable_pages = 600
        precondition(MemoryCollector.memoryTotals(vm).app == 0)
        precondition(MemoryCollector.pressureName(level: 1, available: true) == "normal")
        precondition(MemoryCollector.pressureName(level: 2, available: true) == "warning")
        precondition(MemoryCollector.pressureName(level: 4, available: true) == "critical")
        precondition(MemoryCollector.pressureName(level: 3, available: true) == "unknown")
        precondition(MemoryCollector.pressureName(level: 1, available: false) == "unknown")
    }

    static func testGrouping() {
        func process(_ pid: Int32, _ parent: Int32, _ path: String, _ metric: String = "footprint") -> ProcessMemory {
            ProcessMemory(pid: pid, parentPID: parent, name: "p\(pid)", executablePath: path, bytes: metric == "unavailable" ? 0 : UInt64(pid), metric: metric)
        }
        let input = [
            process(10, 1, "/Applications/Browser.app/Contents/MacOS/Browser"),
            process(11, 1, "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"),
            process(12, 10, "/usr/local/bin/python"),
            process(13, 12, "/usr/local/bin/worker"),
            process(14, 10, "/Applications/Editor.app/Contents/MacOS/Editor"),
            process(15, 1, "/System/Library/Frameworks/WebKit.framework/XPCServices/WebContent"),
            process(16, 1, "/Applications/Unreadable.app/Contents/MacOS/Unreadable", "unavailable"),
            process(17, 18, "/usr/bin/cycle1"), process(18, 17, "/usr/bin/cycle2"),
            process(19, 1, "", "unavailable"),
            process(20, 1, "/usr/local/bin/python")
        ]
        let overrides: [Int32: MemoryCollector.AppDescriptor] = [
            19: .init(name: "Hidden", bundlePath: "/Applications/Hidden.app", executablePath: ""),
            20: .init(name: "Python", bundlePath: "/usr/local/bin/python", executablePath: "/usr/local/bin/python")
        ]
        let groups = MemoryCollector.groupProcesses(input, applications: overrides)
        let browser = groups.first { $0.bundlePath == "/Applications/Browser.app" }!
        precondition(Set(browser.processes.map(\.pid)) == [10, 11, 12, 13])
        precondition(groups.first { $0.bundlePath == "/Applications/Editor.app" }!.processes.count == 1)
        precondition(groups.first { $0.bundlePath == "/Applications/Unreadable.app" }!.processes[0].metric == "unavailable")
        precondition(groups.first { $0.bundlePath == "/Applications/Hidden.app" }!.processes[0].pid == 19)
        precondition(groups.first { $0.processes.contains { $0.pid == 15 } }!.isApplication == false)
        precondition(groups.first { $0.processes.contains { $0.pid == 20 } }!.isApplication == false)
        precondition(groups.flatMap(\.processes).count == input.count)
        precondition(MemoryCollector.outermostAppPath("/opt/apple/bin/tool") == nil)
    }
}
