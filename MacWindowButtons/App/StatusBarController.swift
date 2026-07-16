import AppKit

/// 创建并管理 macOS 顶部菜单栏入口。
///
/// 控制器只把用户操作转换为应用状态变更，不直接执行 Accessibility 操作，
/// 便于后续分别测试菜单、权限和窗口控制模块。
final class StatusBarController: NSObject {
    private let applicationState: ApplicationState
    private let statusItem: NSStatusItem

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
    /// - Parameter applicationState: 跨模块共享的应用运行状态。
    init(applicationState: ApplicationState) {
        self.applicationState = applicationState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusButton()
        configureMenu()
        synchronizeMenuState()

        applicationState.onWindowButtonsEnabledChange = { [weak self] _ in
            // 状态可能由后续后台服务改变，所有 AppKit 更新统一回到主线程。
            DispatchQueue.main.async {
                self?.synchronizeMenuState()
            }
        }
    }

    deinit {
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
}
