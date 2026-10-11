import Foundation
import ServiceManagement

@MainActor
private final class FakeLoginService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registerCount = 0
    var unregisterCount = 0
    var settingsCount = 0
    var registerError = false
    var unregisterError = false
    var registrationStatus: SMAppService.Status = .enabled

    func register() throws {
        registerCount += 1
        if registerError { throw NSError(domain: "MemoryGlass.LoginTests", code: 1) }
        status = registrationStatus
    }
    func unregister() throws {
        unregisterCount += 1
        if unregisterError { throw NSError(domain: "MemoryGlass.LoginTests", code: 2) }
        status = .notRegistered
    }
    func openSystemSettings() { settingsCount += 1 }
}

@MainActor
private final class FakeLoginPreferences: LoginItemPreferences {
    var initialConfigurationAttempted = false
}

@main
enum LoginItemTests {
    @MainActor
    static func main() {
        var checked = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checked += 1
        }

        let outsideService = FakeLoginService()
        let outsidePreferences = FakeLoginPreferences()
        let outside = LoginItemManager(service: outsideService, preferences: outsidePreferences, isInstalled: { false })
        outside.configureInitialLoginItem()
        outside.setEnabled(true)
        expect(outsideService.registerCount == 0, "Do not register from a staging or disk-image path")
        expect(!outside.canEnable && !outsidePreferences.initialConfigurationAttempted, "Installing later must still allow the initial attempt")

        let absentService = FakeLoginService()
        absentService.status = .notFound
        let absentPreferences = FakeLoginPreferences()
        let absent = LoginItemManager(service: absentService, preferences: absentPreferences, isInstalled: { true })
        absent.configureInitialLoginItem()
        expect(absentService.registerCount == 1 && absent.isEnabled, "A fresh missing BTM record must receive its first registration")
        expect(absentPreferences.initialConfigurationAttempted, "The missing-record registration is only attempted once")

        let service = FakeLoginService()
        let preferences = FakeLoginPreferences()
        let manager = LoginItemManager(service: service, preferences: preferences, isInstalled: { true })
        manager.configureInitialLoginItem()
        manager.configureInitialLoginItem()
        expect(service.registerCount == 1 && manager.isEnabled, "Installed first launch registers once")
        manager.setEnabled(false)
        expect(service.unregisterCount == 1 && !manager.isEnabled, "Manual disable follows actual service state")
        let relaunched = LoginItemManager(service: service, preferences: preferences, isInstalled: { true })
        relaunched.configureInitialLoginItem()
        expect(service.registerCount == 1, "A manual disable remains disabled after relaunch")

        service.status = .requiresApproval
        relaunched.refreshStatus()
        relaunched.configureInitialLoginItem()
        expect(!relaunched.isEnabled && relaunched.requiresApproval, "System revocation cannot be reported as enabled")
        expect(service.registerCount == 1 && service.settingsCount == 0, "Startup does not reregister or open Settings after revocation")
        relaunched.setEnabled(true)
        expect(service.settingsCount == 1 && service.registerCount == 1, "Explicit enable of a pending item opens its consent control")

        let pendingService = FakeLoginService()
        pendingService.registrationStatus = .requiresApproval
        let pending = LoginItemManager(service: pendingService, preferences: FakeLoginPreferences(), isInstalled: { true })
        pending.configureInitialLoginItem()
        expect(!pending.isEnabled && pending.requiresApproval, "Successful registration awaiting approval is not enabled")
        expect(pendingService.settingsCount == 0, "First startup awaiting approval remains quiet")

        let failedService = FakeLoginService()
        failedService.registerError = true
        let failedPreferences = FakeLoginPreferences()
        let failed = LoginItemManager(service: failedService, preferences: failedPreferences, isInstalled: { true })
        failed.configureInitialLoginItem()
        failed.configureInitialLoginItem()
        expect(!failed.isEnabled && failed.statusMessage?.contains("无法开启") == true, "Registration failure is visible")
        expect(failedService.registerCount == 1, "Failed startup registration is not repeatedly attempted")
        failedService.registerError = false
        failed.setEnabled(true)
        expect(failedService.registerCount == 2 && failed.isEnabled, "Explicit retry can recover")
        failedService.unregisterError = true
        failed.setEnabled(false)
        expect(failed.isEnabled && failed.statusMessage?.contains("无法关闭") == true, "Failed disable does not claim the system item is disabled")

        let existing = FakeLoginService()
        existing.status = .enabled
        let existingPreferences = FakeLoginPreferences()
        let existingManager = LoginItemManager(service: existing, preferences: existingPreferences, isInstalled: { true })
        existingManager.configureInitialLoginItem()
        expect(existing.registerCount == 0 && existingPreferences.initialConfigurationAttempted, "An existing enabled item is preserved")
        existing.status = .notRegistered
        existingManager.configureInitialLoginItem()
        expect(existing.registerCount == 0, "An external removal remains respected")

        print("Login item tests passed: \(checked) checks; no real login items accessed.")
    }
}
