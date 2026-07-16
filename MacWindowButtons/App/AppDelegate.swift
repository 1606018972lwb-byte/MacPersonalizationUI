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
    private var statusBarController: StatusBarController?
    private var overlayPanelController: OverlayPanelController?

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

    /// 应用完成启动后创建菜单栏控制器。
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 使用菜单栏附件策略：窗口可以正常显示，但应用图标不会进入程序坞。
        NSApp.setActivationPolicy(.accessory)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showMainWindowFromSecondLaunch),
            name: SingleInstanceCoordinator.showMainWindowNotification,
            object: nil
        )

        let windowManager = AccessibilityWindowManager(permissionManager: permissionManager)
        let stateStore = WindowStateStore()
        let actionService = WindowActionService(stateStore: stateStore)
        let overlayController = OverlayPanelController(
            applicationState: applicationState,
            permissionManager: permissionManager,
            windowManager: windowManager,
            actionService: actionService,
            appSettings: appSettings
        )

        let statusController = StatusBarController(
            applicationState: applicationState,
            permissionManager: permissionManager,
            appSettings: appSettings,
            windowRefresher: overlayController
        )
        statusBarController = statusController
        overlayPanelController = overlayController
        overlayController.start()

        // 等待应用完成首次激活后立即显示主界面。
        DispatchQueue.main.async {
            statusController.showControlCenter()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        overlayPanelController?.stop()
    }

    /// 强制启动第二个进程时，由单实例协调器把启动意图转发到这里。
    @objc private func showMainWindowFromSecondLaunch(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController?.showControlCenter()
    }

    /// 应用重新成为活动状态时，如果主界面已关闭，则自动重新显示。
    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let statusBarController = self?.statusBarController,
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
        statusBarController?.showControlCenter()
        // 主界面已由上面的调用恢复，不再请求 AppKit 执行默认的窗口恢复流程。
        return false
    }

    /// 最后一个普通窗口关闭时仍保持菜单栏应用运行。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
