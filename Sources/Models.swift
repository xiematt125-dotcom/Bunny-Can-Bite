import Foundation

struct ProcessIdentity: Codable, Equatable, Hashable, Sendable {
    let seconds: UInt64
    let microseconds: UInt64
}

struct ProcessMemory: Identifiable, Codable, Sendable {
    var id: Int32 { pid }
    let pid: Int32
    let parentPID: Int32
    let name: String
    let executablePath: String
    let bytes: UInt64
    let metric: String // footprint, rss, or unavailable
    let identity: ProcessIdentity?
    let isSystem: Bool?

    init(pid: Int32, parentPID: Int32, name: String, executablePath: String, bytes: UInt64,
         metric: String, identity: ProcessIdentity? = nil, isSystem: Bool? = nil) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.executablePath = executablePath
        self.bytes = bytes
        self.metric = metric
        self.identity = identity
        self.isSystem = isSystem
    }
}

struct AppMemory: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let bundlePath: String?
    let isApplication: Bool
    let processes: [ProcessMemory]
    var bytes: UInt64 { processes.reduce(0) { $0 + $1.bytes } }
}

struct MemorySnapshot: Codable, Sendable {
    let timestamp: Date
    let totalBytes: UInt64
    let usedBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let freeBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64
    let swapAvailable: Bool
    let pressure: String // normal, warning, critical, unknown
    let deviceName: String
    let chipName: String
    let groups: [AppMemory]
    let processCount: Int
    let unavailableCount: Int
    let rssCount: Int
    let collectionDurationMS: Double
    let warnings: [String]
    var usedPercent: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0 }
}

struct MemorySample: Identifiable {
    let id = UUID()
    let date: Date
    let percent: Double
    let pressure: String
}
