import AppKit
import ServiceManagement

/// Whether Earshot opens at login, as the system reports it.
enum LaunchAtLoginStatus: Equatable, Sendable {
    /// Not registered.
    case disabled

    /// Registered and approved.
    case enabled

    /// Registered, but the user must approve it in Login Items settings.
    case requiresApproval
}

/// Registers Earshot as a login item. The status is always read from the
/// system, never stored by Earshot.
@MainActor
protocol LaunchAtLoginService: AnyObject {
    /// The current status.
    var status: LaunchAtLoginStatus { get }

    /// Registers the app to open at login.
    func register() throws

    /// Removes the login item.
    func unregister() throws

    /// Opens System Settings › General › Login Items.
    func openLoginItemsSettings()
}

/// `LaunchAtLoginService` over `SMAppService.mainApp`.
@MainActor
final class SMAppLaunchAtLogin: LaunchAtLoginService {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
