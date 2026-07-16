import AppKit

/// 创建并管理 macOS 顶部菜单栏入口。
///
/// 控制器只把用户操作转换为应用状态变更，不直接执行 Accessibility 操作，
/// 便于后续分别测试菜单、权限和窗口控制模块。
final class StatusBarController: NSObject {
    private let applicationState: ApplicationState
    private let permissionManager: AccessibilityPermissionManager
    private let appSettings: AppSettings
    private let statusItem: NSStatusItem
    private var settingsObserverIdentifier: UUID?
    private var controlSizeItems: [AppSettings.ControlSize: NSMenuItem] = [:]

    private lazy var enableItem = NSMenuItem(
        title: "启用窗口按钮",
        action: #selector(enableWindowButtons),
        keyEquivalent: ""
    )
    private lazy var pauseItem = NSMenuItem(
        title: "暂停窗口按钮",
        action: #selector(pauseWindowButtons),
        keyEquivalent: ""
    )

    /// 创建状态栏图标和菜单。
    /// - Parameters:
    ///   - applicationState: 跨模块共享的应用运行状态。
    ///   - permissionManager: 辅助功能权限检查与设置跳转服务。
    ///   - appSettings: 按钮大小等用户偏好设置。
    init(
        applicationState: ApplicationState,
        permissionManager: AccessibilityPermissionManager,
        appSettings: AppSettings
    ) {
        self.applicationState = applicationState
        self.permissionManager = permissionManager
        self.appSettings = appSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusButton()
        configureMenu()
        synchronizeMenuState()
        synchronizeControlSizeMenu()

        applicationState.onWindowButtonsEnabledChange = { [weak self] _ in
            // 状态可能由后续后台服务改变，所有 AppKit 更新统一回到主线程。
            DispatchQueue.main.async {
                self?.synchronizeMenuState()
            }
        }

        settingsObserverIdentifier = appSettings.addControlSizeObserver { [weak self] _ in
            self?.synchronizeControlSizeMenu()
        }
    }

    deinit {
        if let settingsObserverIdentifier {
            appSettings.removeControlSizeObserver(settingsObserverIdentifier)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            NSLog("[MacWindowButtons] 无法创建菜单栏按钮")
            return
        }

        button.toolTip = "MacWindowButtons"
        button.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "窗口增强工具"
        )

        // 极少数系统环境无法加载 SF Symbol，使用文本作为可见降级方案。
        if button.image == nil {
            button.title = "▣"
        }
    }

    private func configureMenu() {
        let menu = NSMenu()

        enableItem.target = self
        pauseItem.target = self
        menu.addItem(enableItem)
        menu.addItem(pauseItem)
        menu.addItem(.separator())

        let permissionItem = NSMenuItem(
            title: "检查辅助功能权限",
            action: #selector(checkAccessibilityPermission),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        let controlSizeMenu = NSMenu(title: "按钮大小")
        for controlSize in AppSettings.ControlSize.allCases {
            let item = NSMenuItem(
                title: controlSize.displayName,
                action: #selector(changeControlSize(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = controlSize.rawValue
            controlSizeMenu.addItem(item)
            controlSizeItems[controlSize] = item
        }

        let controlSizeItem = NSMenuItem(title: "按钮大小", action: nil, keyEquivalent: "")
        controlSizeItem.submenu = controlSizeMenu
        menu.addItem(controlSizeItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 MacWindowButtons",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// 响应“启用窗口按钮”菜单项。
    @objc private func enableWindowButtons() {
        applicationState.enableWindowButtons()
    }

    /// 响应“暂停窗口按钮”菜单项。
    @objc private func pauseWindowButtons() {
        applicationState.pauseWindowButtons()
    }

    /// 显示权限状态；未授权时可直接进入对应的系统设置页面。
    @objc private func checkAccessibilityPermission() {
        permissionManager.showPermissionStatus()
    }

    /// 从菜单项读取大小标识并保存，悬浮控制条会通过设置监听立即更新。
    @objc private func changeControlSize(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let controlSize = AppSettings.ControlSize(rawValue: rawValue) else {
            NSLog("[MacWindowButtons] 无法识别按钮大小菜单项")
            return
        }
        appSettings.setControlSize(controlSize)
    }

    /// 安全结束应用，由 AppKit 执行完整的终止生命周期。
    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func synchronizeMenuState() {
        let isEnabled = applicationState.areWindowButtonsEnabled
        enableItem.isEnabled = !isEnabled
        pauseItem.isEnabled = isEnabled
        enableItem.state = isEnabled ? .on : .off
        pauseItem.state = isEnabled ? .off : .on
    }

    private func synchronizeControlSizeMenu() {
        for (controlSize, item) in controlSizeItems {
            item.state = controlSize == appSettings.controlSize ? .on : .off
        }
    }
}
