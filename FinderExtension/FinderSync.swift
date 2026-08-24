import AppKit
import FinderSync

/// 为 Finder 选中项提供 Windows 风格的“发送到”子菜单。
final class FinderSync: FIFinderSync {
    private static let requestNotification = Notification.Name(
        "com.lwb.MacWindowButtons.createDesktopShortcuts"
    )
    private static let pathsKey = "paths"

    override init() {
        super.init()
        // 监视文件系统根目录，使普通文件夹和已挂载磁盘都能显示该菜单。
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
              !selectedURLs.isEmpty else {
            return nil
        }

        let menu = NSMenu(title: "")
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
        return menu
    }

    @objc private func sendToDesktop() {
        guard let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
              !selectedURLs.isEmpty else {
            return
        }

        if isContainingApplicationRunning {
            postRequest(for: selectedURLs)
        } else {
            activateContainingApplication { [weak self] in
                self?.postRequest(for: selectedURLs)
            }
        }
    }

    private var isContainingApplicationRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.lwb.MacWindowButtons"
        ).isEmpty
    }

    private func activateContainingApplication(completion: @escaping () -> Void) {
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog("[MacWindowButtonsFinder] 无法启动主程序：%@", error.localizedDescription)
                return
            }
            // 等主程序完成 applicationDidFinishLaunching 并注册分布式通知监听。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: completion)
        }
    }

    private func postRequest(for urls: [URL]) {
        DistributedNotificationCenter.default().post(
            name: Self.requestNotification,
            object: nil,
            userInfo: [Self.pathsKey: urls.map(\.path)]
        )
    }
}
