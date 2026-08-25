import AppKit
import Darwin

/// 使用用户临时目录中的 POSIX 文件锁保证整个登录会话只有一个应用进程。
///
/// 文件描述符在主进程整个生命周期内保持打开；即使应用崩溃或被强制结束，macOS 也会
/// 自动释放锁，不会留下阻止下次启动的“死锁文件”。第二个进程只负责唤醒已有实例。
private final class SingleInstanceCoordinator {
    static let showMainWindowNotification = Notification.Name(
        "com.lwb.MacWindowButtons.showMainWindow"
    )

    private var lockFileDescriptor: Int32 = -1

    func acquireLock() -> Bool {
        let lockURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("com.lwb.MacWindowButtons.instance.lock")
        lockFileDescriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard lockFileDescriptor >= 0 else {
            NSLog("[MacWindowButtons] 无法创建单实例锁：%@", lockURL.path)
            return false
        }

        guard Darwin.lockf(lockFileDescriptor, F_TLOCK, 0) == 0 else {
            Darwin.close(lockFileDescriptor)
            lockFileDescriptor = -1
            return false
        }
        return true
    }

    /// 通知已经运行的进程显示主界面，并将它切换到前台。
    func activateRunningInstance() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName(Self.showMainWindowNotification.rawValue as CFString),
            nil,
            nil,
            true
        )

        let currentPID = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.lwb.MacWindowButtons"
        )
        .first { $0.processIdentifier != currentPID && !$0.isTerminated }?
        .activate(options: [.activateAllWindows])
    }

    deinit {
        guard lockFileDescriptor >= 0 else {
            return
        }
        _ = Darwin.lockf(lockFileDescriptor, F_ULOCK, 0)
        Darwin.close(lockFileDescriptor)
    }
}

/// 应用生命周期入口。
///
/// 本类只负责组合应用级对象。菜单展示由 `StatusBarController` 负责，
/// 功能开关状态由 `ApplicationState` 负责，避免把后续窗口控制逻辑堆积在入口中。
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let singleInstanceCoordinator: SingleInstanceCoordinator
    private let applicationState = ApplicationState()
    private let permissionManager = AccessibilityPermissionManager()
    private let appSettings = AppSettings()
    private let launchAtLoginController = LaunchAtLoginController()
    private let licenseManager = LicenseManager()
    private lazy var activationWindowController = ActivationWindowController(
        licenseManager: licenseManager
    )
    private lazy var updateManager = UpdateManager(appSettings: appSettings)
    private lazy var deleteShortcutController = DeleteToTrashShortcutController(
        appSettings: appSettings
    )
    private lazy var inputMethodShortcutController = InputMethodShortcutController(
        appSettings: appSettings
    )
    private lazy var finderContextMenuController = FinderContextMenuController(
        appSettings: appSettings
    )
    private lazy var desktopShortcutController = DesktopShortcutController(
        appSettings: appSettings
    )
    private var statusBarController: StatusBarController?
    private var overlayPanelController: OverlayPanelController?
    private var licensedFeaturesRunning = false

    private init(singleInstanceCoordinator: SingleInstanceCoordinator) {
        self.singleInstanceCoordinator = singleInstanceCoordinator
        super.init()
    }

    /// 无 Storyboard 项目的显式启动入口。
    ///
    /// AppKit 模板通常由 Main.storyboard 创建并连接应用代理。本项目完全使用代码构建
    /// 界面，因此必须在进入事件循环前自行创建代理并赋给 NSApplication；否则
    /// applicationDidFinishLaunching 不会执行，也就不会创建主窗口和菜单栏图标。
    static func main() {
        let singleInstanceCoordinator = SingleInstanceCoordinator()
        guard singleInstanceCoordinator.acquireLock() else {
            singleInstanceCoordinator.activateRunningInstance()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate(singleInstanceCoordinator: singleInstanceCoordinator)
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    /// 应用完成启动后先验证许可证，只有授权有效时才启动实际功能。
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 使用菜单栏附件策略：窗口可以正常显示，但应用图标不会进入程序坞。
        NSApp.setActivationPolicy(.accessory)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showMainWindowFromSecondLaunch),
            name: SingleInstanceCoordinator.showMainWindowNotification,
            object: nil
        )
        licenseManager.onStateChange = { [weak self] state in
            self?.applyLicenseState(state, isInitialLaunch: false)
        }
        licenseManager.startMonitoring()
        applyLicenseState(licenseManager.state, isInitialLaunch: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        overlayPanelController?.stop()
        deleteShortcutController.stop()
        inputMethodShortcutController.stop()
        finderContextMenuController.stop()
        updateManager.stop()
        licenseManager.stopMonitoring()
    }

    /// 接收 Sandbox Finder 扩展通过自定义 URL scheme 发来的快捷方式请求。
    func application(_ application: NSApplication, open urls: [URL]) {
        licenseManager.refresh()
        guard licenseManager.state.isActive else {
            activationWindowController.show()
            return
        }
        for url in urls {
            _ = desktopShortcutController.handle(url)
        }
    }

    /// 强制启动第二个进程时，由单实例协调器把启动意图转发到这里。
    @objc private func showMainWindowFromSecondLaunch(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        licenseManager.refresh()
        if licenseManager.state.isActive {
            statusBarController?.showControlCenter()
        } else {
            activationWindowController.show()
        }
    }

    /// 应用重新成为活动状态时，如果主界面已关闭，则自动重新显示。
    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if !licenseManager.state.isActive {
                if !activationWindowController.isVisible {
                    activationWindowController.show()
                }
                return
            }
            guard !appSettings.launchesSilently,
                  let statusBarController,
                  !statusBarController.isControlCenterVisible else {
                return
            }
            statusBarController.showControlCenter()
        }
    }

    /// 应用已经运行时再次从 Finder 双击，重新打开控制中心而不是静默忽略。
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        sender.setActivationPolicy(.accessory)
        licenseManager.refresh()
        if licenseManager.state.isActive {
            statusBarController?.showControlCenter()
        } else {
            activationWindowController.show()
        }
        // 主界面已由上面的调用恢复，不再请求 AppKit 执行默认的窗口恢复流程。
        return false
    }

    /// 最后一个普通窗口关闭时仍保持菜单栏应用运行。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func applyLicenseState(
        _ state: LicenseState,
        isInitialLaunch: Bool
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state.isActive else {
            stopLicensedFeatures()
            activationWindowController.refreshState()
            activationWindowController.show()
            return
        }

        let wasShowingActivation = activationWindowController.isVisible
        startLicensedFeatures()
        activationWindowController.closeAfterActivation()
        if wasShowingActivation || (isInitialLaunch && !appSettings.launchesSilently) {
            DispatchQueue.main.async { [weak self] in
                self?.statusBarController?.showControlCenter()
            }
        }
    }

    private func startLicensedFeatures() {
        guard !licensedFeaturesRunning else {
            return
        }
        let overlayController: OverlayPanelController
        if let existingController = overlayPanelController {
            overlayController = existingController
        } else {
            let windowManager = AccessibilityWindowManager(
                permissionManager: permissionManager
            )
            let stateStore = WindowStateStore()
            let actionService = WindowActionService(stateStore: stateStore)
            overlayController = OverlayPanelController(
                applicationState: applicationState,
                permissionManager: permissionManager,
                windowManager: windowManager,
                actionService: actionService,
                appSettings: appSettings
            )
            overlayPanelController = overlayController
        }

        if statusBarController == nil {
            statusBarController = StatusBarController(
                applicationState: applicationState,
                permissionManager: permissionManager,
                appSettings: appSettings,
                launchAtLoginController: launchAtLoginController,
                updateManager: updateManager,
                inputMethodShortcutController: inputMethodShortcutController,
                finderContextMenuController: finderContextMenuController,
                windowRefresher: overlayController
            )
        }
        overlayController.start()
        deleteShortcutController.start()
        inputMethodShortcutController.start()
        finderContextMenuController.start()
        updateManager.start()
        licensedFeaturesRunning = true
    }

    private func stopLicensedFeatures() {
        guard licensedFeaturesRunning else {
            finderContextMenuController.stop()
            return
        }
        overlayPanelController?.stop()
        deleteShortcutController.stop()
        inputMethodShortcutController.stop()
        finderContextMenuController.stop()
        updateManager.stop()
        statusBarController = nil
        licensedFeaturesRunning = false
    }
}
