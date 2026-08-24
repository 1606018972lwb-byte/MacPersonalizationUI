import AppKit

/// 管理菜单栏小图标，以及启动、双击或点击图标后显示的控制中心窗口。
final class StatusBarController: NSObject {
    private let permissionManager: AccessibilityPermissionManager
    private let updateManager: UpdateManager
    private let statusItem: NSStatusItem
    private let controlCenterViewController: ControlCenterViewController
    private let controlCenterWindow: NSWindow
    private lazy var contextMenu = makeContextMenu()

    private var permissionTimer: Timer?
    private var lastKnownPermissionState: Bool?

    /// 供应用生命周期判断再次激活时是否需要恢复主界面。
    var isControlCenterVisible: Bool {
        controlCenterWindow.isVisible
    }

    init(
        applicationState: ApplicationState,
        permissionManager: AccessibilityPermissionManager,
        appSettings: AppSettings,
        launchAtLoginController: LaunchAtLoginController,
        updateManager: UpdateManager,
        inputMethodShortcutController: InputMethodShortcutController,
        finderContextMenuController: FinderContextMenuController,
        windowRefresher: WindowOverlayRefreshing
    ) {
        self.permissionManager = permissionManager
        self.updateManager = updateManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        controlCenterViewController = ControlCenterViewController(
            applicationState: applicationState,
            permissionManager: permissionManager,
            appSettings: appSettings,
            launchAtLoginController: launchAtLoginController,
            updateManager: updateManager,
            inputMethodShortcutController: inputMethodShortcutController,
            finderContextMenuController: finderContextMenuController,
            windowRefresher: windowRefresher
        )
        controlCenterWindow = NSWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 640, height: 500)),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        configureStatusButton()
        configureControlCenterWindow()
        startPermissionMonitoring()
        updateManager.onUpdateAvailable = { [weak self] release in
            self?.showUpdateAvailable(release)
        }
    }

    deinit {
        permissionTimer?.invalidate()
        controlCenterWindow.orderOut(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            NSLog("[MacWindowButtons] 无法创建菜单栏按钮")
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.isVisible = true
        updateStatusButtonAppearance()
    }

    private func configureControlCenterWindow() {
        controlCenterWindow.title = "MacWindowButtons 设置"
        controlCenterWindow.titleVisibility = .visible
        controlCenterWindow.titlebarAppearsTransparent = false
        controlCenterWindow.appearance = NSAppearance(named: .darkAqua)
        controlCenterWindow.isReleasedWhenClosed = false
        controlCenterWindow.hidesOnDeactivate = false
        controlCenterWindow.isMovableByWindowBackground = false
        // 主界面使用普通窗口层级，可由菜单栏图标或再次双击应用置前。
        controlCenterWindow.level = .normal
        controlCenterWindow.collectionBehavior = [.moveToActiveSpace]
        controlCenterWindow.contentViewController = controlCenterViewController
        controlCenterWindow.center()
    }

    /// 左键打开控制中心；右键显示设置、重启和退出菜单。
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            showControlCenter()
            return
        }

        if event.type == .rightMouseUp {
            NSMenu.popUpContextMenu(contextMenu, with: event, for: sender)
        } else {
            toggleControlCenter()
        }
    }

    private func toggleControlCenter() {
        if controlCenterWindow.isVisible {
            controlCenterWindow.orderOut(nil)
        } else {
            showControlCenter()
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "MacWindowButtons")
        menu.autoenablesItems = false

        let settingsItem = NSMenuItem(
            title: "打开设置界面",
            action: #selector(openSettingsInterface),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)

        let finderExtensionItem = NSMenuItem(
            title: "打开 Finder 扩展设置",
            action: #selector(openFinderExtensionSettings),
            keyEquivalent: ""
        )
        finderExtensionItem.target = self
        finderExtensionItem.isEnabled = true
        menu.addItem(finderExtensionItem)
        menu.addItem(.separator())

        let restartItem = NSMenuItem(
            title: "重新启动软件",
            action: #selector(restartApplication),
            keyEquivalent: ""
        )
        restartItem.target = self
        restartItem.isEnabled = true
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(
            title: "退出程序",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openSettingsInterface() {
        showControlCenter()
    }

    @objc private func openFinderExtensionSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 先启动一个短生命周期的系统助手，当前进程退出并释放单实例锁后再打开应用。
    @objc private func restartApplication() {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 应用路径作为独立参数传入，固定脚本只引用 $1，避免路径中的空格被错误拆分。
        helper.arguments = [
            "-c",
            "sleep 0.6; /usr/bin/open \"$1\"",
            "MacWindowButtons-RestartHelper",
            Bundle.main.bundlePath
        ]

        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            showRestartError(error)
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    /// 主动打开控制中心。应用首次启动和用户再次双击应用时都会调用。
    func showControlCenter() {
        dispatchPrecondition(condition: .onQueue(.main))
        // 保持附件应用策略，打开主界面时也不让程序坞图标重新出现。
        NSApp.setActivationPolicy(.accessory)
        updateStatusButtonAppearance()
        controlCenterViewController.refreshInterface()

        if !controlCenterWindow.isVisible {
            controlCenterWindow.center()
        }

        // UIElement 附件应用不会因普通 activate() 自动置前，必须显式忽略其他应用；
        // orderFrontRegardless 确保首次双击和菜单栏点击都能看到主界面。
        NSApp.activate(ignoringOtherApps: true)
        controlCenterWindow.makeKeyAndOrderFront(nil)
        controlCenterWindow.orderFrontRegardless()
        NSLog("[MacWindowButtons] 控制中心已显示")

        // 已经授权时，打开主界面会主动重新扫描窗口；未授权时只显示状态卡，
        // 不在每次启动或双击时反复弹出系统权限窗口。
        if permissionManager.isTrusted {
            controlCenterViewController.refreshWindowsAfterPermissionGrant()
        }
    }

    private func startPermissionMonitoring() {
        lastKnownPermissionState = permissionManager.isTrusted
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            let currentState = permissionManager.isTrusted
            if currentState != lastKnownPermissionState {
                lastKnownPermissionState = currentState
                updateStatusButtonAppearance()
                controlCenterViewController.refreshInterface()
                if currentState {
                    controlCenterViewController.refreshWindowsAfterPermissionGrant()
                }
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func updateStatusButtonAppearance() {
        guard let button = statusItem.button else {
            return
        }

        let isTrusted = permissionManager.isTrusted
        if lastKnownPermissionState != isTrusted {
            NSLog(
                "[MacWindowButtons] 辅助功能权限状态：%@",
                isTrusted ? "已授权" : "未授权"
            )
        }
        lastKnownPermissionState = isTrusted

        let symbolName = isTrusted
            ? "macwindow.on.rectangle"
            : "exclamationmark.triangle.fill"
        let description = isTrusted
            ? "打开 MacWindowButtons"
            : "MacWindowButtons 缺少辅助功能权限"
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        button.toolTip = description
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: description
        )?.withSymbolConfiguration(configuration)
        // 模板图标由系统根据菜单栏背景自动绘制为白色或黑色，蓝色菜单栏上也清晰可见。
        button.image?.isTemplate = true
        button.contentTintColor = nil

        // 极少数系统环境无法加载 SF Symbol，使用醒目的文本降级方案。
        if button.image == nil {
            button.title = isTrusted ? "▣" : "⚠︎"
        } else {
            button.title = ""
        }
    }

    private func showRestartError(_ error: Error) {
        showRestartErrorMessage(error.localizedDescription)
    }

    private func showRestartErrorMessage(_ detail: String) {
        showControlCenter()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法重新启动 MacWindowButtons"
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: controlCenterWindow)
    }

    private func showUpdateAvailable(_ release: UpdateRelease) {
        showControlCenter()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现 MacWindowButtons \(release.version)"
        alert.informativeText = "更新来自 \(release.source.rawValue)。你可以打开发行页面查看说明并下载安装。"
        alert.addButton(withTitle: "查看新版本")
        alert.addButton(withTitle: "稍后")
        alert.beginSheetModal(for: controlCenterWindow) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.updateManager.openLatestReleasePage()
            }
        }
    }
}
