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

/// 使用 AXObserver 接收窗口移动、缩放和焦点变化事件，避免依赖低频轮询追随。
private final class AccessibilityWindowTracker {
    enum Change {
        case geometry
        case focusOrLifecycle
    }

    private var observer: AXObserver?
    private var applicationElement: AXUIElement?
    private var windowElement: AXUIElement?
    private var trackedIdentifier: WindowIdentifier?
    private let onWindowChanged: (Change) -> Void

    init(onWindowChanged: @escaping (Change) -> Void) {
        self.onWindowChanged = onWindowChanged
    }

    func track(_ window: TargetWindow) {
        guard trackedIdentifier != window.identifier else {
            return
        }
        stop()

        var newObserver: AXObserver?
        let result = AXObserverCreate(
            window.processIdentifier,
            accessibilityWindowChangeCallback,
            &newObserver
        )
        guard result == .success, let newObserver else {
            return
        }

        let application = AXUIElementCreateApplication(window.processIdentifier)
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            newObserver,
            application,
            kAXFocusedWindowChangedNotification as CFString,
            context
        )
        for notification in [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXUIElementDestroyedNotification
        ] {
            AXObserverAddNotification(
                newObserver,
                window.element,
                notification as CFString,
                context
            )
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
        observer = newObserver
        applicationElement = application
        windowElement = window.element
        trackedIdentifier = window.identifier
    }

    func stop() {
        guard let observer else {
            trackedIdentifier = nil
            return
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        self.observer = nil
        applicationElement = nil
        windowElement = nil
        trackedIdentifier = nil
    }

    fileprivate func windowDidChange(notification: CFString) {
        let name = notification as String
        let change: Change = name == kAXMovedNotification as String
            || name == kAXResizedNotification as String
            ? .geometry
            : .focusOrLifecycle

        // Observer 的 RunLoopSource 已安装在主线程。直接处理可省去一次异步排队，
        // 快速拖动时也不会积压一长串已经过期的位置更新。
        if Thread.isMainThread {
            onWindowChanged(change)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onWindowChanged(change)
            }
        }
    }

    deinit {
        stop()
    }
}

private let accessibilityWindowChangeCallback: AXObserverCallback = {
    _, _, notification, context in
    guard let context else {
        return
    }
    Unmanaged<AccessibilityWindowTracker>
        .fromOpaque(context)
        .takeUnretainedValue()
        .windowDidChange(notification: notification)
}

/// 事件驱动跟随焦点窗口、代理空白行拖动，并转发三个窗口控制动作。
final class OverlayPanelController: NSObject, WindowOverlayRefreshing {
    private let applicationState: ApplicationState
    private let permissionManager: AccessibilityPermissionManager
    private let windowManager: AccessibilityWindowManager
    private let actionService: WindowActionService
    private let appSettings: AppSettings
    private let panel: OverlayPanel
    private let buttonsView: WindowButtonsView

    private var refreshTimer: Timer?
    private var motionTrackingTimer: Timer?
    private var motionTrackingDeadline = Date.distantPast
    private var currentWindow: TargetWindow?
    private var lastExternalWindow: TargetWindow?
    private var settingsObserverIdentifier: UUID?
    private var appearanceObserverIdentifier: UUID?
    private var workspaceObserver: NSObjectProtocol?
    private var globalMouseMonitor: Any?
    private var dragWindow: TargetWindow?
    private var dragStartMouseLocation: CGPoint?
    private var dragStartAccessibilityFrame: CGRect?
    private var dragStartAppKitFrame: CGRect?
    private lazy var windowTracker = AccessibilityWindowTracker { [weak self] change in
        self?.trackedWindowDidChange(change)
    }

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
        applyControlAppearance(appSettings.controlAppearance)
        settingsObserverIdentifier = appSettings.addControlSizeObserver { [weak self] controlSize in
            self?.applyControlSize(controlSize)
        }
        appearanceObserverIdentifier = appSettings.addControlAppearanceObserver {
            [weak self] appearance in
            self?.applyControlAppearance(appearance)
        }
    }

    deinit {
        if let settingsObserverIdentifier {
            appSettings.removeControlSizeObserver(settingsObserverIdentifier)
        }
        if let appearanceObserverIdentifier {
            appSettings.removeControlAppearanceObserver(appearanceObserverIdentifier)
        }
        stop()
    }

    /// AXObserver 负责实时跟随；1 秒轮询只作为不支持通知的应用的兼容兜底。
    func start() {
        guard refreshTimer == nil else {
            return
        }

        refreshOverlay()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshOverlay()
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleGlobalMouseEvent(event)
            }
        }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshOverlay()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// 停止窗口跟随并隐藏控制条。
    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        stopMotionTracking()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        windowTracker.stop()
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
            windowTracker.stop()
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
        buttonsView.autoresizingMask = [.width, .height]
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
        buttonsView.onEmptyAreaDragBegan = { [weak self] mouseLocation in
            self?.beginDraggingTargetWindow(at: mouseLocation)
        }
        buttonsView.onEmptyAreaDragged = { [weak self] mouseLocation in
            self?.dragTargetWindow(to: mouseLocation)
        }
        buttonsView.onEmptyAreaDragEnded = { [weak self] in
            self?.endDraggingTargetWindow()
        }
    }

    private func refreshOverlay() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard applicationState.areWindowButtonsEnabled,
              permissionManager.isTrusted else {
            currentWindow = nil
            windowTracker.stop()
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
            windowTracker.stop()
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
            windowTracker.stop()
            hideOverlay()
            return
        }

        currentWindow = targetWindow
        lastExternalWindow = targetWindow
        windowTracker.track(targetWindow)
        buttonsView.updateCapabilities(
            for: targetWindow,
            showsRestore: actionService.isMaximizedByThisApp(targetWindow)
        )

        positionOverlay(using: appKitFrame)
    }

    /// 只更新面板几何位置，不重新读取焦点应用、窗口标题和按钮能力。
    /// 原生窗口拖动期间走此快速路径，可显著减少 AX 查询和主线程排队。
    private func positionOverlay(using appKitFrame: CGRect) {
        let overlaySize = CGSize(
            width: appKitFrame.width,
            height: appSettings.controlSize.buttonHeight
        )
        if panel.frame.size != overlaySize {
            panel.setContentSize(overlaySize)
            buttonsView.frame = CGRect(origin: .zero, size: overlaySize)
        }
        panel.setFrameOrigin(
            CGPoint(
                x: appKitFrame.minX,
                y: appKitFrame.maxY - appSettings.controlAppearance.windowOverlap
            )
        )
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func trackedWindowDidChange(_ change: AccessibilityWindowTracker.Change) {
        switch change {
        case .geometry:
            motionTrackingDeadline = Date().addingTimeInterval(0.18)
            updateOverlayFromTrackedWindow()
            startMotionTrackingIfNeeded()
        case .focusOrLifecycle:
            stopMotionTracking()
            refreshOverlay()
        }
    }

    /// 部分应用会降低 AXMoved 通知频率。全局鼠标拖动事件可更早触发一次坐标读取，
    /// 但只有窗口实际移动时才启动高频计时器，普通内容拖拽不会增加持续负载。
    private func handleGlobalMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            if updateOverlayFromTrackedWindow() {
                motionTrackingDeadline = Date().addingTimeInterval(0.18)
                startMotionTrackingIfNeeded()
            }
        case .leftMouseUp:
            motionTrackingDeadline = Date().addingTimeInterval(0.05)
        default:
            break
        }
    }

    /// 原生标题栏拖动时，AXMoved 通知的频率和到达时间由目标应用决定。
    /// 收到首个几何通知后短时以最高 120Hz 直接读取已跟踪 AX 元素；鼠标仍按下时
    /// 持续跟踪，释放后在最后一个通知的收尾窗口结束，不影响平时功耗。
    private func startMotionTrackingIfNeeded() {
        guard motionTrackingTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            updateOverlayFromTrackedWindow()
            let isPrimaryMouseButtonPressed = NSEvent.pressedMouseButtons & 1 == 1
            if !isPrimaryMouseButtonPressed && Date() >= motionTrackingDeadline {
                stopMotionTracking()
                // 结束后执行一次完整刷新，校正焦点、能力和最终尺寸。
                refreshOverlay()
            }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        motionTrackingTimer = timer
    }

    private func stopMotionTracking() {
        motionTrackingTimer?.invalidate()
        motionTrackingTimer = nil
        motionTrackingDeadline = .distantPast
    }

    @discardableResult
    private func updateOverlayFromTrackedWindow() -> Bool {
        guard let updatedWindow = currentWindow?.refreshingFrame(),
              let appKitFrame = ScreenCoordinateConverter.appKitRect(
                fromAccessibilityRect: updatedWindow.frame
              ) else {
            return false
        }
        let didGeometryChange = updatedWindow.frame != currentWindow?.frame
        currentWindow = updatedWindow
        lastExternalWindow = updatedWindow
        if didGeometryChange {
            positionOverlay(using: appKitFrame)
        }
        return didGeometryChange
    }

    private func hideOverlay() {
        stopMotionTracking()
        panel.orderOut(nil)
    }

    private func beginDraggingTargetWindow(at mouseLocation: CGPoint) {
        guard let currentWindow,
              let appKitFrame = ScreenCoordinateConverter.appKitRect(
                fromAccessibilityRect: currentWindow.frame
              ) else {
            return
        }
        dragWindow = currentWindow
        dragStartMouseLocation = mouseLocation
        dragStartAccessibilityFrame = currentWindow.frame
        dragStartAppKitFrame = appKitFrame
    }

    private func dragTargetWindow(to mouseLocation: CGPoint) {
        guard let dragWindow,
              let dragStartMouseLocation,
              let dragStartAccessibilityFrame,
              let dragStartAppKitFrame else {
            return
        }

        let delta = CGPoint(
            x: mouseLocation.x - dragStartMouseLocation.x,
            y: mouseLocation.y - dragStartMouseLocation.y
        )
        let accessibilityPosition = CGPoint(
            x: dragStartAccessibilityFrame.minX + delta.x,
            y: dragStartAccessibilityFrame.minY - delta.y
        )
        _ = actionService.move(dragWindow, to: accessibilityPosition)

        // 面板先在当前鼠标事件内移动，目标窗口的 AX 通知随后再校准位置。
        panel.setFrameOrigin(
            CGPoint(
                x: dragStartAppKitFrame.minX + delta.x,
                y: dragStartAppKitFrame.maxY
                    + delta.y
                    - appSettings.controlAppearance.windowOverlap
            )
        )
    }

    private func endDraggingTargetWindow() {
        dragWindow = nil
        dragStartMouseLocation = nil
        dragStartAccessibilityFrame = nil
        dragStartAppKitFrame = nil
        refreshOverlay()
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
            reservedTopHeight: reservedTopHeight
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
        if let currentWindow {
            _ = actionService.updateReservedTopSpace(
                for: currentWindow,
                reservedTopHeight: reservedTopHeight
            )
        }
        refreshOverlay()
    }

    private func applyControlAppearance(_ appearance: AppSettings.ControlAppearance) {
        dispatchPrecondition(condition: .onQueue(.main))
        buttonsView.applyAppearance(appearance)
        panel.hasShadow = appearance == .floating
        if let currentWindow {
            _ = actionService.updateReservedTopSpace(
                for: currentWindow,
                reservedTopHeight: reservedTopHeight
            )
        }
        refreshOverlay()
    }

    private var reservedTopHeight: CGFloat {
        max(
            0,
            appSettings.controlSize.buttonHeight
                - appSettings.controlAppearance.windowOverlap
        )
    }
}
