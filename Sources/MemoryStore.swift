import AppKit
import Combine
import Foundation

@MainActor
final class MemoryStore: ObservableObject {
    @Published private(set) var snapshot: MemorySnapshot?
    @Published private(set) var samples: [MemorySample] = []
    @Published private(set) var isCollecting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isTerminating = false
    @Published private(set) var terminationReport: TerminationReport?
    @Published var isPaused = false { didSet { updateTimer(); if !isPaused { refresh() } } }
    @Published var refreshInterval: Double = 2 { didSet { updateTimer() } }

    private let collector = MemoryCollector()
    private let terminator = ProcessTerminator()
    private let queue = DispatchQueue(label: "MemoryGlass.collector", qos: .utility)
    private var timer: Timer?

    init() {
        updateTimer()
        refresh()
    }

    func refresh() {
        guard !isCollecting, !isTerminating else { return }
        isCollecting = true
        let collector = self.collector
        queue.async { [weak self] in
            let result = Result { try collector.collect() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCollecting = false
                switch result {
                case .success(let value):
                    self.snapshot = value
                    self.errorMessage = nil
                    self.samples.append(MemorySample(date: value.timestamp, percent: value.usedPercent, pressure: value.pressure))
                    let cutoff = value.timestamp.addingTimeInterval(-30 * 60)
                    self.samples.removeAll { $0.date < cutoff }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func prepareTermination() {
        guard !isTerminating else { return }
        terminationReport = nil
    }

    func performTermination(_ request: TerminationRequest) {
        guard !isTerminating else { return }
        isTerminating = true
        terminationReport = nil
        let terminator = self.terminator
        // Use the collection queue so process reads and termination never overlap.
        queue.async { [weak self] in
            let report = terminator.terminate(request)
            DispatchQueue.main.async {
                guard let self else { return }
                self.terminationReport = report
                self.isTerminating = false
                // A user action always refreshes the list, including while paused.
                self.refresh()
            }
        }
    }

    private func updateTimer() {
        timer?.invalidate()
        timer = nil
        guard !isPaused else { return }
        // Default mode avoids rebuilding SwiftUI controls while a native picker
        // menu is tracking. Sampling continues normally with the window closed.
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let existing = icons[path] { return existing }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 36, height: 36)
        icons[path] = image
        return image
    }
}
