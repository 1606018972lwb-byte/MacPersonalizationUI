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

    /// 应用完成启动后创建菜单栏控制器。
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist 已通过 LSUIElement 隐藏 Dock 图标；此处再次指定 accessory
        // 激活策略，确保从命令行或调试器启动时也保持菜单栏应用行为。
        NSApp.setActivationPolicy(.accessory)

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

        statusBarController = StatusBarController(
            applicationState: applicationState,
            permissionManager: permissionManager,
            appSettings: appSettings
        )
        overlayPanelController = overlayController
        overlayController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayPanelController?.stop()
    }

    /// 最后一个普通窗口关闭时仍保持菜单栏应用运行。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
