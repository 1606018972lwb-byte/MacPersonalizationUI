import AppKit

/// 管理菜单栏小图标，以及启动、双击或点击图标后显示的控制中心窗口。
final class StatusBarController: NSObject {
    private let permissionManager: AccessibilityPermissionManager
    private let statusItem: NSStatusItem
    private let controlCenterViewController: ControlCenterViewController
    private let controlCenterWindow: NSPanel
    private lazy var contextMenu = makeContextMenu()

    private var permissionTimer: Timer?
    private var lastKnownPermissionState: Bool?
    private var hasPresentedMissingPermissionAlert = false

    init(
        applicationState: ApplicationState,
        permissionManager: AccessibilityPermissionManager,
        appSettings: AppSettings
    ) {
        self.permissionManager = permissionManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        controlCenterViewController = ControlCenterViewController(
            applicationState: applicationState,
            permissionManager: permissionManager,
            appSettings: appSettings
        )
        controlCenterWindow = NSPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 340, height: 330)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        configureStatusButton()
        configureControlCenterWindow()
        startPermissionMonitoring()
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
        controlCenterWindow.title = "MacWindowButtons"
        controlCenterWindow.titleVisibility = .hidden
        controlCenterWindow.titlebarAppearsTransparent = true
        controlCenterWindow.isReleasedWhenClosed = false
        controlCenterWindow.hidesOnDeactivate = false
        controlCenterWindow.isMovableByWindowBackground = true
        controlCenterWindow.level = .floating
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

    /// 创建同一安装位置的新实例；确认启动成功后再退出当前实例。
    @objc private func restartApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] application, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showRestartError(error)
                    return
                }

                guard application != nil else {
                    self?.showRestartErrorMessage("系统没有返回新的应用实例。")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    /// 主动打开控制中心。应用首次启动和用户再次双击应用时都会调用。
    func showControlCenter() {
        dispatchPrecondition(condition: .onQueue(.main))
        updateStatusButtonAppearance()
        controlCenterViewController.refreshInterface()

        if !controlCenterWindow.isVisible {
            controlCenterWindow.center()
        }

        // macOS 14 提供无参数激活接口；macOS 13 使用当时仍有效的兼容接口。
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        controlCenterWindow.makeKeyAndOrderFront(nil)
        NSLog("[MacWindowButtons] 控制中心已显示")

        if !permissionManager.isTrusted, !hasPresentedMissingPermissionAlert {
            hasPresentedMissingPermissionAlert = true
            DispatchQueue.main.async { [weak self] in
                self?.permissionManager.requestPermissionFromUser()
            }
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
}
