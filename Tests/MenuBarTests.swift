import Foundation

@main
struct MenuBarTests {
    static func main() {
        testApplicationSelection()
        testStatusPresentation()
        testPopoverPresentation()
        print("PASS: menu-bar top-10 selection, stable ties, percentages, loading/paused/error/stale/live states")
    }

    private static func group(_ id: String, bytes: UInt64, app: Bool = true, metric: String = "footprint") -> AppMemory {
        AppMemory(id: id, name: id, bundlePath: app ? "/Applications/\(id).app" : nil, isApplication: app,
                  processes: [.init(pid: 99, parentPID: 1, name: id, executablePath: "", bytes: bytes, metric: metric)])
    }

    private static func snapshot(_ groups: [AppMemory]) -> MemorySnapshot {
        .init(timestamp: Date(timeIntervalSince1970: 100), totalBytes: 10_000, usedBytes: 7_500,
              appBytes: 5_000, wiredBytes: 1_000, compressedBytes: 1_500, cachedBytes: 1_000,
              freeBytes: 1_500, swapUsedBytes: 0, swapTotalBytes: 0, swapAvailable: true, pressure: "normal",
              deviceName: "Test Mac", chipName: "Test", groups: groups, processCount: groups.count,
              unavailableCount: 0, rssCount: 0, collectionDurationMS: 1, warnings: [])
    }

    private static func testApplicationSelection() {
        let apps = (1...14).map { group("app\($0)", bytes: UInt64($0) * 100) }
        let input = snapshot([group("huge-daemon", bytes: 9_999, app: false),
                              group("zero", bytes: 0), group("unreadable", bytes: 0, metric: "unavailable")] + apps.reversed())
        let top = MenuBarMemoryPresentation.topApplications(in: input)
        precondition(top.count == 10)
        precondition(MenuBarMemoryPresentation.topApplications(in: input, limit: 50).count == 10)
        precondition(top.map(\.bytes) == (5...14).reversed().map { UInt64($0) * 100 })
        precondition(top.allSatisfy { $0.isApplication && $0.bytes > 0 })
        precondition(MenuBarMemoryPresentation.topApplications(in: input, limit: 3).count == 3)
        precondition(MenuBarMemoryPresentation.topApplications(in: input, limit: 0).isEmpty)
        precondition(MenuBarMemoryPresentation.topApplications(in: input, limit: -1).isEmpty)
        precondition(MenuBarMemoryPresentation.topApplications(in: nil).isEmpty)
        let tie = snapshot([group("z", bytes: 400), group("a", bytes: 400), group("b", bytes: 900)])
        precondition(MenuBarMemoryPresentation.topApplications(in: tie).map(\.id) == ["b", "a", "z"])
    }

    private static func testStatusPresentation() {
        let sample = Date(timeIntervalSince1970: 100)
        func status(percent: Double? = 75.1, date: Date? = sample, paused: Bool = false,
                    error: String? = nil, interval: TimeInterval = 2, now: TimeInterval = 101) -> MemoryStatusPresentation {
            .make(percent: percent, snapshotDate: date, isPaused: paused, errorMessage: error,
                  refreshInterval: interval, now: Date(timeIntervalSince1970: now))
        }
        precondition(status().title == "75.1%")
        precondition(status().detail.contains("实时采样"))
        precondition(status().detail.contains("浮层"))
        precondition(status(paused: true, now: 200).title == "⏸ 75.1%")
        precondition(status(paused: true, error: "oops").detail.contains("已暂停"))
        precondition(status(error: "读取失败").title == "! 75.1%")
        precondition(status(error: "读取失败").detail.contains("读取失败"))
        precondition(status(now: 116).detail.contains("已过期"))
        precondition(status(now: 115).title == "75.1%")
        precondition(status(interval: 10, now: 130).title == "75.1%")
        precondition(status(interval: 10, now: 131).title == "! 75.1%")
        precondition(status(percent: nil, date: nil).title == "--%")
        precondition(status(percent: nil, date: nil).detail.contains("尚无可用采样"))
    }

    private static func testPopoverPresentation() {
        let sample = Date(timeIntervalSince1970: 100)
        func state(date: Date? = sample, paused: Bool = false, error: String? = nil, now: TimeInterval = 101) -> String {
            MenuBarMemoryPresentation.samplingState(snapshotDate: date, isPaused: paused, errorMessage: error,
                                                    refreshInterval: 2, now: Date(timeIntervalSince1970: now))
        }
        precondition(state() == "实时更新")
        precondition(state(paused: true, now: 200).contains("已暂停"))
        precondition(state(error: "failure").contains("采样异常"))
        precondition(state(now: 116) == "数据已过期")
        precondition(state(date: nil) == "正在读取")
        precondition(MenuBarMemoryPresentation.percentage(10, total: 0) == 0)
        precondition(MenuBarMemoryPresentation.groupPercentage(group("p", bytes: 500), total: 10_000) == "5.0%")
        precondition(MenuBarMemoryPresentation.groupPercentage(group("p", bytes: 500, metric: "unavailable"), total: 10_000) == "≥5.0%")
        precondition(MenuBarMemoryPresentation.pressureName("normal") == "压力正常")
        precondition(MenuBarMemoryPresentation.pressureName(nil) == "压力未知")
    }
}
