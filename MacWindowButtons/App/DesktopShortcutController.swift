import Foundation

enum DesktopShortcutNaming {
    static func availableDestination(
        sourceName: String,
        desktopURL: URL,
        style: AppSettings.DesktopShortcutNameStyle,
        fileExists: (String) -> Bool
    ) -> URL {
        let baseName = style.baseName(for: sourceName)
        var destinationURL = desktopURL.appendingPathComponent(baseName)
        var copyNumber = 1

        while fileExists(destinationURL.path) {
            destinationURL = desktopURL.appendingPathComponent(
                "\(baseName) (\(copyNumber))"
            )
            copyNumber += 1
        }
        return destinationURL
    }
}

/// 接收 Finder 扩展发来的选中项，并在用户桌面创建 Finder 别名。
final class DesktopShortcutController {
    private static let requestScheme = "macwindowbuttons"
    private static let requestHost = "create-desktop-shortcuts"

    private enum RequestKey {
        static let paths = "paths"
    }

    private let appSettings: AppSettings
    private let fileManager: FileManager

    init(
        appSettings: AppSettings,
        fileManager: FileManager = .default
    ) {
        self.appSettings = appSettings
        self.fileManager = fileManager
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == Self.requestScheme,
              url.host == Self.requestHost,
              let components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              ),
              let encodedPaths = components.queryItems?.first(
                  where: { $0.name == RequestKey.paths }
              )?.value,
              let pathData = Data(base64Encoded: encodedPaths),
              let paths = try? JSONDecoder().decode([String].self, from: pathData) else {
            return false
        }

        createDesktopShortcuts(forPaths: Array(paths.prefix(100)))
        return true
    }

    private func createDesktopShortcuts(forPaths paths: [String]) {
        guard let desktopURL = try? fileManager.url(
            for: .desktopDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            NSLog("[MacWindowButtons] 无法定位用户桌面")
            return
        }

        for path in paths {
            let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            do {
                let bookmarkData = try sourceURL.bookmarkData(
                    options: .suitableForBookmarkFile,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                let destinationURL = availableDestination(
                    for: sourceURL,
                    on: desktopURL
                )
                try URL.writeBookmarkData(bookmarkData, to: destinationURL)
            } catch {
                NSLog(
                    "[MacWindowButtons] 创建桌面快捷方式失败（%@）：%@",
                    sourceURL.path,
                    error.localizedDescription
                )
            }
        }

    }

    private func availableDestination(for sourceURL: URL, on desktopURL: URL) -> URL {
        let displayName = NSMetadataItem(url: sourceURL)?.value(
            forAttribute: NSMetadataItemDisplayNameKey
        ) as? String ?? sourceURL.lastPathComponent
        let sourceName = (displayName as NSString).deletingPathExtension
        return DesktopShortcutNaming.availableDestination(
            sourceName: sourceName,
            desktopURL: desktopURL,
            style: appSettings.desktopShortcutNameStyle
        ) { path in
            fileManager.fileExists(atPath: path)
        }
    }
}
