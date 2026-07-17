import AppKit
import ServiceManagement

/// 使用 macOS 13 的 SMAppService 管理主应用登录项。
final class LaunchAtLoginController {
    enum State {
        case enabled
        case disabled
        case requiresApproval
        case unavailable

        var isEnabled: Bool {
            self == .enabled
        }
    }

    var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
