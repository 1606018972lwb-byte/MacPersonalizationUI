import AppKit

/// 手动刷新全部运行中应用窗口后的结果。
struct WindowRefreshResult {
    let discoveredWindowCount: Int
    let targetApplicationName: String?
    let areControlsVisible: Bool
}

/// 主界面通过该协议请求刷新，无需了解悬浮面板内部实现。
protocol WindowOverlayRefreshing: AnyObject {
    func refreshAllWindows() -> WindowRefreshResult
}

/// 永远不成为主窗口或键盘焦点的悬浮面板。
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 轮询焦点窗口、定位悬浮面板并转发三个窗口控制动作。
final class OverlayPanelController: NSObject, WindowOverlayRefreshing {
    private let applicationState: ApplicationState
    private let permissionManager: AccessibilityPermissionManager
    private let windowManager: AccessibilityWindowManager
    private let actionService: WindowActionService
    private let appSettings: AppSettings
    private let panel: OverlayPanel
    private let buttonsView: WindowButtonsView

    private var refreshTimer: Timer?
    private var currentWindow: TargetWindow?
    private var lastExternalWindow: TargetWindow?
    private var settingsObserverIdentifier: UUID?

    init(
        applicationState: ApplicationState,
        permissionManager: AccessibilityPermissionManager,
        windowManager: AccessibilityWindowManager,
        actionService: WindowActionService,
        appSettings: AppSettings
    ) {
        self.applicationState = applicationState
        self.permissionManager = permissionManager
        self.windowManager = windowManager
        self.actionService = actionService
        self.appSettings = appSettings

        panel = OverlayPanel(
            contentRect: CGRect(origin: .zero, size: appSettings.controlSize.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        buttonsView = WindowButtonsView(
            frame: CGRect(origin: .zero, size: appSettings.controlSize.panelSize)
        )
        super.init()

        configurePanel()
        configureActions()
        applyControlSize(appSettings.controlSize)
        settingsObserverIdentifier = appSettings.addControlSizeObserver { [weak self] controlSize in
            self?.applyControlSize(controlSize)
        }
    }

    deinit {
        if let settingsObserverIdentifier {
            appSettings.removeControlSizeObserver(settingsObserverIdentifier)
        }
        stop()
    }

    /// 启动 200ms 低频兼容轮询，让面板跟随移动、缩放和应用切换。
    func start() {
        guard refreshTimer == nil else {
            return
        }

        refreshOverlay()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.refreshOverlay()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// 停止窗口跟随并隐藏控制条。
    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        currentWindow = nil
        hideOverlay()
    }

    /// 扫描全部普通应用窗口，并立即为最近的外部目标窗口显示三个控件。
    func refreshAllWindows() -> WindowRefreshResult {
        dispatchPrecondition(condition: .onQueue(.main))
        applicationState.enableWindowButtons()

        let discoveredWindows = windowManager.allControllableWindows()
        let preferredWindow = lastExternalWindow.flatMap { previousWindow in
            discoveredWindows.first { window in
                window.identifier == previousWindow.identifier
            }
        } ?? discoveredWindows.first

        if let preferredWindow {
            displayOverlay(for: preferredWindow)
        } else {
            currentWindow = nil
            hideOverlay()
        }

        return WindowRefreshResult(
            discoveredWindowCount: discoveredWindows.count,
            targetApplicationName: preferredWindow?.applicationName,
            areControlsVisible: preferredWindow != nil && panel.isVisible
        )
    }

    private func configurePanel() {
        panel.contentView = buttonsView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
    }

    private func configureActions() {
        buttonsView.minimizeButton.target = self
        buttonsView.minimizeButton.action = #selector(minimizeWindow)
        buttonsView.maximizeButton.target = self
        buttonsView.maximizeButton.action = #selector(toggleMaximizeWindow)
        buttonsView.closeButton.target = self
        buttonsView.closeButton.action = #selector(closeWindow)
    }

    private func refreshOverlay() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard applicationState.areWindowButtonsEnabled,
              permissionManager.isTrusted else {
            currentWindow = nil
            hideOverlay()
            return
        }

        guard let targetWindow = windowManager.focusedWindow() else {
            // 控制中心成为前台时继续展示最近的外部窗口，避免手动刷新结果被定时器立刻隐藏。
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                == Bundle.main.bundleIdentifier,
               let lastExternalWindow {
                displayOverlay(for: lastExternalWindow)
                return
            }
            currentWindow = nil
            hideOverlay()
            return
        }

        displayOverlay(for: targetWindow)
    }

    private func displayOverlay(for targetWindow: TargetWindow) {
        guard let appKitFrame = ScreenCoordinateConverter.appKitRect(
            fromAccessibilityRect: targetWindow.frame
        ) else {
            currentWindow = nil
            hideOverlay()
            return
        }

        currentWindow = targetWindow
        lastExternalWindow = targetWindow
        buttonsView.updateCapabilities(
            for: targetWindow,
            showsRestore: actionService.isMaximizedByThisApp(targetWindow)
        )

        // 控制条紧贴窗口右上角的外侧显示，不占用或覆盖目标应用标题栏。
        // 使用本工具最大化时，WindowActionService 会在窗口上方预留同样高度的一整行。
        let origin = CGPoint(
            x: appKitFrame.maxX - appSettings.controlSize.panelSize.width,
            y: appKitFrame.maxY
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func hideOverlay() {
        panel.orderOut(nil)
    }

    @objc private func minimizeWindow() {
        guard let currentWindow else {
            return
        }
        if actionService.minimize(currentWindow) {
            hideOverlay()
        }
    }

    @objc private func toggleMaximizeWindow() {
        guard let currentWindow else {
            return
        }
        _ = actionService.toggleMaximize(
            currentWindow,
            reservedTopHeight: appSettings.controlSize.buttonHeight
        )
        refreshOverlayAfterAction()
    }

    @objc private func closeWindow() {
        guard let currentWindow else {
            return
        }
        if actionService.close(currentWindow) {
            hideOverlay()
        }
    }

    private func refreshOverlayAfterAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.refreshOverlay()
        }
    }

    private func applyControlSize(_ controlSize: AppSettings.ControlSize) {
        dispatchPrecondition(condition: .onQueue(.main))
        buttonsView.applyControlSize(controlSize)
        panel.setContentSize(controlSize.panelSize)
        if let currentWindow {
            _ = actionService.updateReservedTopSpace(
                for: currentWindow,
                reservedTopHeight: controlSize.buttonHeight
            )
        }
        refreshOverlay()
    }
}
