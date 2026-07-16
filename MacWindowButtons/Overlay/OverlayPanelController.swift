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
    private enum Layout {
        /// 控制条位于标题栏下方，避免遮挡目标应用右上角原生工具按钮。
        static let topClearance: CGFloat = 52
        static let revealHandleWidth: CGFloat = 7
        static let revealDuration: TimeInterval = 0.9
        static let manualRevealDuration: TimeInterval = 2.0
    }

    private let applicationState: ApplicationState
    private let permissionManager: AccessibilityPermissionManager
    private let windowManager: AccessibilityWindowManager
    private let actionService: WindowActionService
    private let appSettings: AppSettings
    private let panel: OverlayPanel
    private let revealHandlePanel: OverlayPanel
    private let buttonsView: WindowButtonsView

    private var refreshTimer: Timer?
    private var currentWindow: TargetWindow?
    private var lastExternalWindow: TargetWindow?
    private var revealUntil: TimeInterval = 0
    private var settingsObserverIdentifier: UUID?
    private var autoHideObserverIdentifier: UUID?

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
        revealHandlePanel = OverlayPanel(
            contentRect: CGRect(
                origin: .zero,
                size: CGSize(
                    width: Layout.revealHandleWidth,
                    height: appSettings.controlSize.buttonHeight
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        buttonsView = WindowButtonsView(
            frame: CGRect(origin: .zero, size: appSettings.controlSize.panelSize)
        )
        super.init()

        configurePanel()
        configureRevealHandlePanel()
        configureActions()
        applyControlSize(appSettings.controlSize)
        settingsObserverIdentifier = appSettings.addControlSizeObserver { [weak self] controlSize in
            self?.applyControlSize(controlSize)
        }
        autoHideObserverIdentifier = appSettings.addAutoHideObserver { [weak self] _ in
            self?.refreshOverlay()
        }
    }

    deinit {
        if let settingsObserverIdentifier {
            appSettings.removeControlSizeObserver(settingsObserverIdentifier)
        }
        if let autoHideObserverIdentifier {
            appSettings.removeAutoHideObserver(autoHideObserverIdentifier)
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
        hideOverlayAndHandle()
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
            revealUntil = ProcessInfo.processInfo.systemUptime + Layout.manualRevealDuration
            displayOverlay(for: preferredWindow)
        } else {
            currentWindow = nil
            hideOverlayAndHandle()
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

    /// 右侧边缘只保留一个不会拦截点击的细提示条；鼠标进入后展开完整控制条。
    private func configureRevealHandlePanel() {
        let handleView = NSView()
        handleView.wantsLayer = true
        handleView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.72).cgColor
        handleView.layer?.cornerRadius = Layout.revealHandleWidth / 2
        revealHandlePanel.contentView = handleView
        revealHandlePanel.backgroundColor = .clear
        revealHandlePanel.isOpaque = false
        revealHandlePanel.hasShadow = false
        revealHandlePanel.hidesOnDeactivate = false
        revealHandlePanel.isMovable = false
        revealHandlePanel.level = .floating
        revealHandlePanel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        // 提示条本身完全点击穿透，不会挡住目标应用下方的内容。
        revealHandlePanel.ignoresMouseEvents = true
        revealHandlePanel.animationBehavior = .none
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
            hideOverlayAndHandle()
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
            hideOverlayAndHandle()
            return
        }

        displayOverlay(for: targetWindow)
    }

    private func displayOverlay(for targetWindow: TargetWindow) {
        guard let appKitFrame = ScreenCoordinateConverter.appKitRect(
            fromAccessibilityRect: targetWindow.frame
        ) else {
            currentWindow = nil
            hideOverlayAndHandle()
            return
        }

        currentWindow = targetWindow
        lastExternalWindow = targetWindow
        buttonsView.updateCapabilities(
            for: targetWindow,
            showsRestore: actionService.isMaximizedByThisApp(targetWindow)
        )

        let origin = CGPoint(
            x: appKitFrame.maxX - appSettings.controlSize.panelSize.width,
            y: appKitFrame.maxY
                - Layout.topClearance
                - appSettings.controlSize.panelSize.height
        )
        panel.setFrameOrigin(origin)
        updateVisibility(for: appKitFrame, panelOrigin: origin)
    }

    private func updateVisibility(for windowFrame: CGRect, panelOrigin: CGPoint) {
        guard appSettings.automaticallyHidesControls else {
            revealHandlePanel.orderOut(nil)
            panel.orderFrontRegardless()
            return
        }

        let handleFrame = CGRect(
            x: windowFrame.maxX - Layout.revealHandleWidth,
            y: panelOrigin.y,
            width: Layout.revealHandleWidth,
            height: appSettings.controlSize.buttonHeight
        )
        revealHandlePanel.setFrame(handleFrame, display: true)

        let mouseLocation = NSEvent.mouseLocation
        let isOverHandle = handleFrame.insetBy(dx: -4, dy: -4).contains(mouseLocation)
        let isOverControls = panel.frame.insetBy(dx: -4, dy: -4).contains(mouseLocation)
        let now = ProcessInfo.processInfo.systemUptime
        if isOverHandle || isOverControls {
            revealUntil = now + Layout.revealDuration
        }

        if now <= revealUntil {
            revealHandlePanel.orderOut(nil)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
            revealHandlePanel.orderFrontRegardless()
        }
    }

    private func hideOverlayAndHandle() {
        panel.orderOut(nil)
        revealHandlePanel.orderOut(nil)
    }

    @objc private func minimizeWindow() {
        guard let currentWindow else {
            return
        }
        if actionService.minimize(currentWindow) {
            hideOverlayAndHandle()
        }
    }

    @objc private func toggleMaximizeWindow() {
        guard let currentWindow else {
            return
        }
        _ = actionService.toggleMaximize(currentWindow)
        refreshOverlayAfterAction()
    }

    @objc private func closeWindow() {
        guard let currentWindow else {
            return
        }
        if actionService.close(currentWindow) {
            hideOverlayAndHandle()
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
        revealHandlePanel.setContentSize(
            CGSize(width: Layout.revealHandleWidth, height: controlSize.buttonHeight)
        )
        refreshOverlay()
    }
}
