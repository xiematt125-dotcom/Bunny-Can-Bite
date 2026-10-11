import AppKit
import Combine
import Foundation
import SwiftUI

/// The value and its freshness are formatted together so an old sample can never
/// silently look like a live menu-bar reading.
struct MemoryStatusPresentation: Equatable {
    let title: String
    let detail: String

    static func make(percent: Double?, snapshotDate: Date?, isPaused: Bool,
                     errorMessage: String?, refreshInterval: TimeInterval,
                     now: Date) -> MemoryStatusPresentation {
        let value = percent.map { String(format: "%.1f%%", $0) } ?? "--%"
        let age = snapshotDate.map { max(0, now.timeIntervalSince($0)) }
        let isStale = age.map { $0 > max(15, refreshInterval * 3) } ?? false
        let state: String
        let mark: String
        if isPaused {
            state = "已暂停自动采样，显示上次读取的数值。"
            mark = "⏸ "
        } else if let errorMessage {
            state = "采样异常，显示上次可用数值：\(errorMessage)"
            mark = "! "
        } else if isStale {
            state = "数据已过期，正在等待新采样；此数值不是当前实时值。"
            mark = "! "
        } else if percent == nil {
            state = "正在读取内存，尚无可用采样。"
            mark = ""
        } else {
            state = "正在实时采样，每 \(Int(refreshInterval)) 秒刷新。"
            mark = ""
        }
        var detail = "Memory Glass · 内存使用率 \(value)\n\(state)"
        if let snapshotDate {
            detail += "\n上次采样：\(snapshotDate.formatted(date: .omitted, time: .standard))"
        }
        detail += "\n点按查看内存浮层 · 右键查看更多操作"
        return MemoryStatusPresentation(title: mark + value, detail: detail)
    }
}

@MainActor
final class MemoryStatusItem: NSObject {
    private let statusItem: NSStatusItem
    private let store: MemoryStore
    private let loginItem: LoginItemManager
    private let popover = NSPopover()
    private let openDashboard: () -> Void
    private var observation: AnyCancellable?
    private var freshnessTimer: Timer?

    init(store: MemoryStore, loginItem: LoginItemManager, openDashboard: @escaping () -> Void) {
        self.store = store
        self.loginItem = loginItem
        self.openDashboard = openDashboard
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "内存使用率")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // objectWillChange precedes the published assignment. Rendering on the
        // next main-queue turn reads the newly committed values.
        observation = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
        freshnessTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        render()
    }

    private func render() {
        let presentation = MemoryStatusPresentation.make(percent: store.snapshot?.usedPercent,
                                                          snapshotDate: store.snapshot?.timestamp,
                                                          isPaused: store.isPaused,
                                                          errorMessage: store.errorMessage,
                                                          refreshInterval: store.refreshInterval,
                                                          now: Date())
        guard let button = statusItem.button else { return }
        button.title = " " + presentation.title
        button.toolTip = presentation.detail
        button.setAccessibilityLabel("Memory Glass 内存监测")
        button.setAccessibilityValue(presentation.detail)
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        showPopover()
    }

    func showPopover() {
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
            return
        }
        guard let button = statusItem.button else { return }
        loginItem.refreshStatus()
        let availableHeight = (button.window?.screen?.visibleFrame.height ?? 900) - 44
        let height = min(680, max(360, availableHeight))
        let view = MenuBarPopoverView(store: store, loginItem: loginItem, height: height,
                                     openDashboard: { [weak self] in self?.openPanel() },
                                     quit: { NSApp.terminate(nil) })
        popover.contentViewController = NSHostingController(rootView: view)
        popover.contentSize = NSSize(width: 384, height: height)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        popover.performClose(nil)
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开内存面板", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let pause = NSMenuItem(title: store.isPaused ? "继续实时采样" : "暂停实时采样", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        loginItem.refreshStatus()
        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = loginItem.isEnabled ? .on : .off
        login.isEnabled = loginItem.canEnable
        menu.autoenablesItems = false
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Memory Glass", action: #selector(quitApplication), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        // An explicit menu popup preserves the status item's direct left-click
        // action; assigning statusItem.menu would make every click open a menu.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func openPanel() {
        popover.performClose(nil)
        openDashboard()
    }
    @objc private func toggleLoginItem() { loginItem.setEnabled(!loginItem.isEnabled) }
    @objc private func togglePause() { store.isPaused.toggle() }
    @objc private func quitApplication() { NSApp.terminate(nil) }
}
