import AppKit

/// 应用生命周期入口。
///
/// 本类只负责组合应用级对象。菜单展示由 `StatusBarController` 负责，
/// 功能开关状态由 `ApplicationState` 负责，避免把后续窗口控制逻辑堆积在入口中。
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let applicationState = ApplicationState()
    private let permissionManager = AccessibilityPermissionManager()
    private let appSettings = AppSettings()
    private var statusBarController: StatusBarController?
    private var overlayPanelController: OverlayPanelController?

    /// 无 Storyboard 项目的显式启动入口。
    ///
    /// AppKit 模板通常由 Main.storyboard 创建并连接应用代理。本项目完全使用代码构建
    /// 界面，因此必须在进入事件循环前自行创建代理并赋给 NSApplication；否则应用虽会
    /// 出现在程序坞，但 applicationDidFinishLaunching 不会执行，也就不会创建主窗口。
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    /// 应用完成启动后创建菜单栏控制器。
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 使用普通前台应用策略：程序坞显示应用图标，用户再次点击或双击应用时
        // 系统能够把激活事件交给 applicationShouldHandleReopen。
        NSApp.setActivationPolicy(.regular)

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

        // 等待应用完成首次激活后立即显示主界面，避免双击应用后只看到程序坞图标。
        DispatchQueue.main.async {
            statusController.showControlCenter()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayPanelController?.stop()
    }

    /// 用户从程序坞点回应用时，如果主界面已关闭，则自动重新显示。
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
        sender.setActivationPolicy(.regular)
        statusBarController?.showControlCenter()
        // 主界面已由上面的调用恢复，不再请求 AppKit 执行默认的窗口恢复流程。
        return false
    }

    /// 最后一个普通窗口关闭时仍保持菜单栏应用运行。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
