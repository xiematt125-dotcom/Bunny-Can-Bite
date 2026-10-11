import AppKit
import Foundation
import os

/// Collected on one serial background queue. No subprocesses, remote access, or privileges.
final class MemoryCollector: Sendable {
    private let bundleNames = OSAllocatedUnfairLock(initialState: [String: String]())
    private let hardwareModel = MemoryCollector.sysctlString("hw.model")
    private let chip = MemoryCollector.sysctlString("machdep.cpu.brand_string")

    struct AppDescriptor {
        let name: String
        let bundlePath: String
        let executablePath: String
    }

    struct Totals {
        let app: UInt64
        let wired: UInt64
        let compressed: UInt64
        let used: UInt64
        let cached: UInt64
        let free: UInt64
    }

    func collect() throws -> MemorySnapshot {
        let start = ProcessInfo.processInfo.systemUptime
        var vm = CMGlobalMemory()
        let globalError = cm_read_global(&vm)
        guard globalError == 0, vm.total_bytes > 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(globalError), userInfo: [NSLocalizedDescriptionKey: "暂时无法读取系统内存数据。"])
        }
        var processCount = 0
        var processError: Int32 = 0
        guard let buffer = cm_copy_processes(&processCount, &processError) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(processError), userInfo: [NSLocalizedDescriptionKey: "暂时无法读取进程列表。"])
        }
        defer { cm_free_processes(buffer) }
        var processes = UnsafeBufferPointer(start: buffer, count: processCount).map { item in
            let path = Self.fixedCString(item.path)
            let rawName = Self.fixedCString(item.name)
            return ProcessMemory(
                pid: item.pid,
                parentPID: item.parent_pid,
                name: rawName.isEmpty ? (path.isEmpty ? "进程 \(item.pid)" : URL(fileURLWithPath: path).lastPathComponent) : rawName,
                executablePath: path,
                bytes: item.memory_bytes,
                metric: item.metric == 1 ? "footprint" : item.metric == 2 ? "rss" : "unavailable",
                identity: item.identity_available != 0
                    ? ProcessIdentity(seconds: item.start_seconds, microseconds: item.start_microseconds) : nil,
                isSystem: item.identity_available != 0 ? item.is_system != 0 : nil
            )
        }
        // Workspace metadata supplies an app identity even when proc_pidpath is denied.
        // Retain an unreadable live app in the list instead of silently dropping it.
        var applicationInfo: [Int32: AppDescriptor] = [:]
        let sampledPIDs = Set(processes.map(\.pid))
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            guard app.processIdentifier > 0, let path = app.bundleURL?.path,
                  let outer = Self.outermostAppPath(path) else { continue }
            let name = app.localizedName ?? URL(fileURLWithPath: outer).deletingPathExtension().lastPathComponent
            let executable = app.executableURL?.path ?? ""
            applicationInfo[app.processIdentifier] = AppDescriptor(name: name, bundlePath: outer, executablePath: executable)
            if !sampledPIDs.contains(app.processIdentifier) {
                processes.append(ProcessMemory(pid: app.processIdentifier, parentPID: 0, name: name, executablePath: executable, bytes: 0, metric: "unavailable"))
            }
        }
        let grouped = Self.groupProcesses(processes, applications: applicationInfo) { [self] path in
            bundleNames.withLock { names in
                if let name = names[path] { return name }
                let bundle = Bundle(path: path)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                names[path] = name
                return name
            }
        }
        let totals = Self.memoryTotals(vm)
        let unavailable = processes.filter { $0.metric == "unavailable" }.count
        let rss = processes.filter { $0.metric == "rss" }.count
        let pressure = Self.pressureName(level: vm.pressure_level, available: vm.pressure_available != 0)
        var warnings: [String] = []
        if unavailable > 0 { warnings.append("\(unavailable) 个进程的内存不可读取；显示已知占用，不计作真实零占用。") }
        if rss > 0 { warnings.append("\(rss) 个进程使用 RSS 回退值，可能重复计入共享内存。") }
        if pressure == "unknown" { warnings.append("系统未提供可识别的内存压力状态。") }
        if vm.swap_available == 0 { warnings.append("交换内存数据暂时不可读取；当前显示值不代表零占用。") }
        // Mac16,10 is the attached Mac mini; do not guess marketing names for other Macs.
        let device = hardwareModel == "Mac16,10" ? "Mac mini" : (hardwareModel.isEmpty ? "Mac" : hardwareModel)
        return MemorySnapshot(
            timestamp: Date(), totalBytes: vm.total_bytes, usedBytes: totals.used,
            appBytes: totals.app, wiredBytes: totals.wired, compressedBytes: totals.compressed,
            cachedBytes: totals.cached, freeBytes: totals.free,
            swapUsedBytes: vm.swap_used_bytes, swapTotalBytes: vm.swap_total_bytes, swapAvailable: vm.swap_available != 0,
            pressure: pressure, deviceName: device, chipName: chip.isEmpty ? "未知芯片" : chip,
            groups: grouped, processCount: processes.count, unavailableCount: unavailable, rssCount: rss,
            collectionDurationMS: (ProcessInfo.processInfo.systemUptime - start) * 1_000,
            warnings: warnings
        )
    }

    static func memoryTotals(_ vm: CMGlobalMemory) -> Totals {
        // Estimates from the VM subsystem, independent of the per-process sum.
        // Purgeable pages are reclaimable; compressor pages are physical storage.
        let app = (vm.internal_pages > vm.purgeable_pages ? vm.internal_pages - vm.purgeable_pages : 0) * vm.page_size
        let wired = vm.wired_pages * vm.page_size
        let compressed = vm.compressed_pages * vm.page_size
        return Totals(app: app, wired: wired, compressed: compressed,
                      used: min(vm.total_bytes, app + wired + compressed),
                      cached: (vm.external_pages + vm.purgeable_pages) * vm.page_size,
                      free: vm.free_pages * vm.page_size)
    }

    static func pressureName(level: Int32, available: Bool) -> String {
        guard available else { return "unknown" }
        switch level {
        case 1: return "normal"
        case 2: return "warning"
        case 4: return "critical"
        default: return "unknown"
        }
    }

    static func outermostAppPath(_ path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else { return nil }
        return (path.hasPrefix("/") ? "/" : "") + components[...index].joined(separator: "/")
    }

    static func groupProcesses(
        _ processes: [ProcessMemory],
        applications: [Int32: AppDescriptor] = [:],
        appName: (String) -> String = { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    ) -> [AppMemory] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var ownApp: [Int32: String] = [:]
        for process in processes {
            // Executable bundle wins over parent, including nested helper applications.
            ownApp[process.pid] = outermostAppPath(process.executablePath)
                ?? applications[process.pid].flatMap { outermostAppPath($0.bundlePath) }
        }
        var grouped: [String: (path: String?, name: String, processes: [ProcessMemory])] = [:]
        for process in processes {
            var path = ownApp[process.pid]
            if path == nil {
                var parent = process.parentPID
                var seen: Set<Int32> = [process.pid]
                for _ in 0..<32 {
                    guard parent > 1, seen.insert(parent).inserted else { break }
                    if let ancestorApp = ownApp[parent] { path = ancestorApp; break }
                    guard let ancestor = byPID[parent] else { break }
                    parent = ancestor.parentPID
                }
            }
            let key = path.map { "app:\($0)" }
                ?? (process.executablePath.isEmpty ? "pid:\(process.pid)" : "service:\(process.executablePath)")
            if grouped[key] == nil {
                grouped[key] = (path, path.map(appName) ?? process.name, [])
            }
            grouped[key]?.processes.append(process)
        }
        return grouped.map { key, item in
            AppMemory(id: key, name: item.name, bundlePath: item.path, isApplication: item.path != nil,
                      processes: item.processes.sorted { $0.bytes == $1.bytes ? $0.pid < $1.pid : $0.bytes > $1.bytes })
        }.sorted {
            if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            return $0.id < $1.id
        }
    }

    private static func fixedCString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }

    private static func sysctlString(_ key: String) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard cm_read_string(key, &buffer, buffer.count) == 0 else { return "" }
        return String(cString: buffer)
    }
}
