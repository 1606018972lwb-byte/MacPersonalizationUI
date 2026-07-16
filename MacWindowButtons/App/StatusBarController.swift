import AppKit

/// 管理菜单栏小图标，以及点击图标后显示的原生控制中心界面。
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let controlCenterViewController: ControlCenterViewController

    init(
        applicationState: ApplicationState,
        permissionManager: AccessibilityPermissionManager,
        appSettings: AppSettings
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        controlCenterViewController = ControlCenterViewController(
            applicationState: applicationState,
            permissionManager: permissionManager,
            appSettings: appSettings
        )
        super.init()

        configureStatusButton()
        configurePopover()
    }

    deinit {
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            NSLog("[MacWindowButtons] 无法创建菜单栏按钮")
            return
        }

        button.toolTip = "打开 MacWindowButtons"
        button.target = self
        button.action = #selector(toggleControlCenter)
        button.sendAction(on: .leftMouseUp)

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "窗口增强工具"
        )?.withSymbolConfiguration(configuration)
        button.image?.isTemplate = true

        // 极少数系统环境无法加载 SF Symbol，使用文本作为可见降级方案。
        if button.image == nil {
            button.title = "▣"
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controlCenterViewController
        popover.contentSize = controlCenterViewController.preferredContentSize
    }

    /// 点击菜单栏小图标时打开或关闭控制中心。
    @objc private func toggleControlCenter() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let button = statusItem.button else {
            NSLog("[MacWindowButtons] 菜单栏按钮已失效，无法打开控制中心")
            return
        }

        controlCenterViewController.refreshInterface()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverWillShow(_ notification: Notification) {
        controlCenterViewController.refreshInterface()
    }
}
