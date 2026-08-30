import AppKit
import FinderSync

/// 为 Finder 选中项提供复制路径和 Windows 风格的“发送到”子菜单。
final class FinderSync: FIFinderSync {
    private enum ConfigurationNotification {
        static let changed = Notification.Name(
            "com.lwb.MacWindowButtons.finder-menu-configuration-changed"
        )
        static let requested = Notification.Name(
            "com.lwb.MacWindowButtons.finder-menu-configuration-requested"
        )
    }

    private enum SettingKey {
        static let copyPathEnabled = "copyPathMenuItemEnabled"
        static let desktopShortcutEnabled = "desktopShortcutMenuItemEnabled"
    }

    private static let requestScheme = "macwindowbuttons"
    private static let requestHost = "create-desktop-shortcuts"
    private static let pathsKey = "paths"
    private var isCopyPathEnabled: Bool
    private var isDesktopShortcutEnabled: Bool
    private var configurationObserver: NSObjectProtocol?

    override init() {
        let defaults = UserDefaults.standard
        isCopyPathEnabled = defaults.object(
            forKey: SettingKey.copyPathEnabled
        ) as? Bool ?? true
        isDesktopShortcutEnabled = defaults.object(
            forKey: SettingKey.desktopShortcutEnabled
        ) as? Bool ?? true
        super.init()
        // 监视文件系统根目录，使普通文件夹和已挂载磁盘都能显示该菜单。
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
        configurationObserver = DistributedNotificationCenter.default().addObserver(
            forName: ConfigurationNotification.changed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.applyConfiguration(notification.object as? String)
        }
        DistributedNotificationCenter.default().post(
            name: ConfigurationNotification.requested,
            object: nil,
            userInfo: nil
        )
    }

    deinit {
        if let configurationObserver {
            DistributedNotificationCenter.default().removeObserver(configurationObserver)
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
              !selectedURLs.isEmpty else {
            return nil
        }

        let menu = NSMenu(title: "")
        if isCopyPathEnabled {
            let copyPathItem = NSMenuItem(
                title: "复制路径",
                action: #selector(copyPaths),
                keyEquivalent: ""
            )
            copyPathItem.target = self
            copyPathItem.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: "复制路径"
            )
            menu.addItem(copyPathItem)
        }
        if isDesktopShortcutEnabled {
            let sendToItem = NSMenuItem(title: "发送到", action: nil, keyEquivalent: "")
            let sendToMenu = NSMenu(title: "发送到")
            let desktopItem = NSMenuItem(
                title: "桌面快捷方式",
                action: #selector(sendToDesktop),
                keyEquivalent: ""
            )
            desktopItem.target = self
            desktopItem.image = NSImage(
                systemSymbolName: "desktopcomputer",
                accessibilityDescription: "桌面快捷方式"
            )
            sendToMenu.addItem(desktopItem)
            sendToItem.submenu = sendToMenu
            menu.addItem(sendToItem)
        }
        return menu.items.isEmpty ? nil : menu
    }

    @objc private func copyPaths() {
        guard let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
              !selectedURLs.isEmpty else {
            return
        }
        let paths = Array(selectedURLs.prefix(100))
            .map { $0.standardizedFileURL.path }
            .joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
    }

    @objc private func sendToDesktop() {
        guard let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
              !selectedURLs.isEmpty else {
            return
        }

        guard let pathData = try? JSONEncoder().encode(
            Array(selectedURLs.prefix(100)).map(\.path)
        ) else {
            return
        }

        var components = URLComponents()
        components.scheme = Self.requestScheme
        components.host = Self.requestHost
        components.queryItems = [
            URLQueryItem(
                name: Self.pathsKey,
                value: pathData.base64EncodedString()
            )
        ]
        guard let requestURL = components.url else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(
            requestURL,
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog(
                    "[MacWindowButtonsFinder] 无法发送桌面快捷方式请求：%@",
                    error.localizedDescription
                )
            }
        }
    }

    private func applyConfiguration(_ configuration: String?) {
        guard let configuration else {
            return
        }
        let values = configuration.split(separator: ",", omittingEmptySubsequences: false)
        guard values.count == 2 else {
            return
        }
        isCopyPathEnabled = values[0] == "1"
        isDesktopShortcutEnabled = values[1] == "1"
        let defaults = UserDefaults.standard
        defaults.set(isCopyPathEnabled, forKey: SettingKey.copyPathEnabled)
        defaults.set(isDesktopShortcutEnabled, forKey: SettingKey.desktopShortcutEnabled)
    }
}
