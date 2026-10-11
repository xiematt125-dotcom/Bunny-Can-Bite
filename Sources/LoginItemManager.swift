import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
protocol LoginItemPreferences: AnyObject {
    var initialConfigurationAttempted: Bool { get set }
}

@MainActor
private final class SystemLoginItemService: LoginItemService {
    private let service = SMAppService.mainApp
    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
private final class SavedLoginItemPreferences: LoginItemPreferences {
    private let key = "MemoryGlass.loginItem.initialConfigurationAttempted.v1"
    var initialConfigurationAttempted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var canEnable = false
    @Published private(set) var requiresApproval = false

    private let service: LoginItemService
    private let preferences: LoginItemPreferences
    private let isInstalled: () -> Bool
    private var operationError: String?

    init(service: LoginItemService? = nil, preferences: LoginItemPreferences? = nil,
         isInstalled: @escaping () -> Bool = {
             Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().path == "/Applications"
         }) {
        self.service = service ?? SystemLoginItemService()
        self.preferences = preferences ?? SavedLoginItemPreferences()
        self.isInstalled = isInstalled
        refreshStatus()
    }

    func refreshStatus() {
        canEnable = isInstalled()
        let status = service.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval

        guard canEnable else {
            statusMessage = "安装到「应用程序」后，可开启登录时自动启动。"
            return
        }
        if let operationError {
            statusMessage = operationError
            return
        }
        switch status {
        case .enabled:
            statusMessage = "登录后自动在菜单栏运行。"
        case .notRegistered:
            statusMessage = "已关闭登录时自动启动。"
        case .requiresApproval:
            statusMessage = "等待系统允许，请在「系统设置 → 通用 → 登录项」中开启。"
        case .notFound:
            statusMessage = "尚未创建登录项，可开启登录时自动启动。"
        @unknown default:
            statusMessage = "暂时无法确认登录项状态。"
        }
    }

    func configureInitialLoginItem() {
        refreshStatus()
        guard canEnable, !preferences.initialConfigurationAttempted else { return }
        // Attempt the explicitly requested default once after installation.
        // Save before registration so a failure or a later user revocation never
        // causes the app to silently keep trying to re-enable itself at launch.
        switch service.status {
        case .notRegistered, .notFound:
            // A fresh main-app login item can be reported as notFound until its
            // first registration creates a Background Task Management record.
            preferences.initialConfigurationAttempted = true
            registerLoginItem()
        case .enabled, .requiresApproval:
            preferences.initialConfigurationAttempted = true
        @unknown default:
            break
        }
    }

    func setEnabled(_ enabled: Bool) {
        operationError = nil
        refreshStatus()
        guard canEnable else { return }
        preferences.initialConfigurationAttempted = true
        if enabled {
            if service.status == .requiresApproval {
                // This explicit request can open the system's consent control;
                // automatic startup registration never opens System Settings.
                openSystemSettings()
            } else if service.status != .enabled {
                registerLoginItem()
            }
        } else if service.status != .notRegistered {
            do {
                try service.unregister()
            } catch {
                operationError = "无法关闭自动启动：\(error.localizedDescription)"
            }
        }
        refreshStatus()
    }

    func openSystemSettings() { service.openSystemSettings() }

    private func registerLoginItem() {
        do {
            try service.register()
        } catch {
            // A denied registration may still be awaiting system approval.
            if service.status != .requiresApproval {
                operationError = "无法开启自动启动：\(error.localizedDescription)"
            }
        }
        refreshStatus()
    }
}
