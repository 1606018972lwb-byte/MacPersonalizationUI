import AppKit
import Foundation

/// 接收 Finder 扩展发来的选中项，并在用户桌面创建 Finder 别名。
final class DesktopShortcutController {
    static let requestNotification = Notification.Name(
        "com.lwb.MacWindowButtons.createDesktopShortcuts"
    )

    private enum RequestKey {
        static let paths = "paths"
    }

    private let fileManager: FileManager
    private var isStarted = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShortcutRequest(_:)),
            name: Self.requestNotification,
            object: nil
        )
    }

    func stop() {
        guard isStarted else {
            return
        }
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Self.requestNotification,
            object: nil
        )
        isStarted = false
    }

    @objc private func handleShortcutRequest(_ notification: Notification) {
        guard let paths = notification.userInfo?[RequestKey.paths] as? [String] else {
            return
        }
        createDesktopShortcuts(forPaths: Array(paths.prefix(100)))
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

        var createdURLs: [URL] = []
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
                createdURLs.append(destinationURL)
            } catch {
                NSLog(
                    "[MacWindowButtons] 创建桌面快捷方式失败（%@）：%@",
                    sourceURL.path,
                    error.localizedDescription
                )
            }
        }

        guard !createdURLs.isEmpty else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(createdURLs)
    }

    private func availableDestination(for sourceURL: URL, on desktopURL: URL) -> URL {
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let baseName = "\(sourceName) - 快捷方式"
        var destinationURL = desktopURL.appendingPathComponent(baseName)
        var copyNumber = 2

        while fileManager.fileExists(atPath: destinationURL.path) {
            destinationURL = desktopURL.appendingPathComponent(
                "\(baseName) (\(copyNumber))"
            )
            copyNumber += 1
        }
        return destinationURL
    }

    deinit {
        stop()
    }
}
