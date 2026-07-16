import AppKit

/// 管理菜单栏小图标，以及启动、双击或点击图标后显示的控制中心窗口。
final class StatusBarController: NSObject {
    private let permissionManager: AccessibilityPermissionManager
    private let statusItem: NSStatusItem
    private let controlCenterViewController: ControlCenterViewController
    private let controlCenterWindow: NSPanel

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
        button.action = #selector(toggleControlCenter)
        button.sendAction(on: .leftMouseUp)
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

    /// 点击菜单栏小图标时打开或关闭控制中心。
    @objc private func toggleControlCenter() {
        if controlCenterWindow.isVisible {
            controlCenterWindow.orderOut(nil)
        } else {
            showControlCenter()
        }
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
        button.image?.isTemplate = isTrusted
        button.contentTintColor = isTrusted ? .labelColor : .systemOrange

        // 极少数系统环境无法加载 SF Symbol，使用醒目的文本降级方案。
        if button.image == nil {
            button.title = isTrusted ? "▣" : "⚠︎"
        } else {
            button.title = ""
        }
    }
}
