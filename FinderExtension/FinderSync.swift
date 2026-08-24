import AppKit
import FinderSync

/// 为 Finder 选中项提供 Windows 风格的“发送到”子菜单。
final class FinderSync: FIFinderSync {
    private static let requestScheme = "macwindowbuttons"
    private static let requestHost = "create-desktop-shortcuts"
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
}
