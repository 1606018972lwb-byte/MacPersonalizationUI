import AppKit

/// 永远不成为主窗口或键盘焦点的悬浮面板。
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 轮询焦点窗口、定位悬浮面板并转发三个窗口控制动作。
final class OverlayPanelController: NSObject {
    private enum Layout {
        static let rightInset: CGFloat = 8
        static let topInset: CGFloat = 5
    }

    private let applicationState: ApplicationState
    private let permissionManager: AccessibilityPermissionManager
    private let windowManager: AccessibilityWindowManager
    private let actionService: WindowActionService
    private let appSettings: AppSettings
    private let panel: OverlayPanel
    private let buttonsView: WindowButtonsView

    private var refreshTimer: Timer?
    private var currentWindow: TargetWindow?
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
        panel.orderOut(nil)
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
              permissionManager.isTrusted,
              let targetWindow = windowManager.focusedWindow(),
              let appKitFrame = ScreenCoordinateConverter.appKitRect(
                fromAccessibilityRect: targetWindow.frame
              ) else {
            currentWindow = nil
            panel.orderOut(nil)
            return
        }

        currentWindow = targetWindow
        buttonsView.updateCapabilities(
            for: targetWindow,
            showsRestore: actionService.isMaximizedByThisApp(targetWindow)
        )

        let origin = CGPoint(
            x: appKitFrame.maxX - appSettings.controlSize.panelSize.width - Layout.rightInset,
            y: appKitFrame.maxY - appSettings.controlSize.panelSize.height - Layout.topInset
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    @objc private func minimizeWindow() {
        guard let currentWindow else {
            return
        }
        if actionService.minimize(currentWindow) {
            panel.orderOut(nil)
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
            panel.orderOut(nil)
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
        if panel.isVisible {
            refreshOverlay()
        }
    }
}
