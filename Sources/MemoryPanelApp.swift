import AppKit
import SwiftUI

@MainActor
final class MemoryGlassDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let store = MemoryStore()
    private let loginItem = LoginItemManager()
    private var statusItem: MemoryStatusItem?
    private var dashboardWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep sampling and the status item independent of the dashboard window.
        NSApp.setActivationPolicy(.accessory)
        installApplicationMenu()
        statusItem = MemoryStatusItem(store: store, loginItem: loginItem) { [weak self] in
            self?.openDashboard()
        }
        loginItem.configureInitialLoginItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A second Finder launch gives feedback via the compact popover. Cold
        // launch and login still create no windows, and existing controls keep
        // their focus when a visible window is already being used.
        if !flag { statusItem?.showPopover() }
        return false
    }

    private func openDashboard() {
        let window: NSWindow
        if let existing = dashboardWindow {
            window = existing
        } else {
            let view = DashboardView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 640)
                .preferredColorScheme(.light)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1160, height: 850),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Memory Glass"
            window.identifier = NSUserInterfaceItemIdentifier("memory-glass")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.contentMinSize = NSSize(width: 900, height: 640)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.collectionBehavior = [.fullScreenPrimary]
            window.contentViewController = NSHostingController(rootView: view)
            window.center()
            dashboardWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let applicationMenu = NSMenu(title: "Memory Glass")
        applicationMenu.addItem(withTitle: "关于 Memory Glass", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "退出 Memory Glass", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        let fileMenu = NSMenu(title: "文件")
        let refresh = fileMenu.addItem(withTitle: "刷新内存数据", action: #selector(refreshMemory(_:)), keyEquivalent: "r")
        refresh.target = self
        let pause = fileMenu.addItem(withTitle: "暂停实时采样", action: #selector(toggleSampling(_:)), keyEquivalent: "p")
        pause.keyEquivalentModifierMask = [.command, .shift]
        pause.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)

        // Preserve standard editing shortcuts for dashboard search fields.
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        menu.addItem(editItem)

        let viewMenu = NSMenu(title: "显示")
        let glance = viewMenu.addItem(withTitle: "内存速览", action: #selector(showMemoryGlance(_:)), keyEquivalent: "1")
        glance.target = self
        let dashboard = viewMenu.addItem(withTitle: "打开完整面板", action: #selector(showDashboard(_:)), keyEquivalent: "2")
        dashboard.target = self
        let viewItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }

    @objc private func refreshMemory(_ sender: Any?) { store.refresh() }
    @objc private func toggleSampling(_ sender: Any?) { store.isPaused.toggle() }
    @objc private func showMemoryGlance(_ sender: Any?) { statusItem?.showPopover() }
    @objc private func showDashboard(_ sender: Any?) { openDashboard() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(refreshMemory(_:)) {
            return !store.isCollecting && !store.isTerminating
        }
        if menuItem.action == #selector(toggleSampling(_:)) {
            menuItem.title = store.isPaused ? "恢复实时采样" : "暂停实时采样"
        }
        return true
    }
}

@main
enum MemoryGlassApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MemoryGlassDelegate()
        application.delegate = delegate
        // NSApplication.delegate is weak, so retain its state for the run loop.
        withExtendedLifetime(delegate) { application.run() }
    }
}
