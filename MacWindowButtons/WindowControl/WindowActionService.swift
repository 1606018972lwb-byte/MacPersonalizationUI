import ApplicationServices

/// 通过 Accessibility API 执行最小化、最大化/还原和关闭操作。
final class WindowActionService {
    private let stateStore: WindowStateStore

    init(stateStore: WindowStateStore) {
        self.stateStore = stateStore
    }

    /// 最小化目标窗口；不支持该属性时返回 false。
    @discardableResult
    func minimize(_ window: TargetWindow) -> Bool {
        guard window.canMinimize else {
            return false
        }
        return window.element.setBooleanAttribute(kAXMinimizedAttribute, value: true)
    }

    /// 将目标窗口移动到指定 AX 坐标；用于把顶部空白控制行变成可拖动标题栏。
    @discardableResult
    func move(_ window: TargetWindow, to position: CGPoint) -> Bool {
        guard window.element.isAttributeSettable(kAXPositionAttribute) else {
            return false
        }
        return window.element.setPointAttribute(kAXPositionAttribute, value: position)
    }

    /// 最大化或还原窗口。最大化使用所在屏幕的 visibleFrame，不进入原生全屏空间。
    @discardableResult
    func toggleMaximize(_ window: TargetWindow, reservedTopHeight: CGFloat) -> Bool {
        guard window.canResize else {
            return false
        }

        if let restoreFrame = stateStore.restoreFrame(for: window.identifier) {
            let didRestore = apply(frame: restoreFrame, to: window.element)
            if didRestore {
                stateStore.removeRestoreFrame(for: window.identifier)
            }
            return didRestore
        }

        guard let screen = ScreenCoordinateConverter.screen(containingAccessibilityRect: window.frame) else {
            NSLog("[MacWindowButtons] 无法确定目标窗口所在显示器")
            return false
        }

        var appKitMaximizeFrame = screen.visibleFrame
        // 最大化窗口顶部主动空出一整行，控制条位于这一行内，不覆盖应用内容。
        appKitMaximizeFrame.size.height = max(
            80,
            appKitMaximizeFrame.height - reservedTopHeight
        )
        guard let maximizeFrame = ScreenCoordinateConverter.accessibilityRect(
                fromAppKitRect: appKitMaximizeFrame
              ) else {
            NSLog("[MacWindowButtons] 无法转换最大化窗口坐标")
            return false
        }

        stateStore.saveRestoreFrame(window.frame, for: window.identifier)
        let didMaximize = apply(frame: maximizeFrame, to: window.element)
        if !didMaximize {
            stateStore.removeRestoreFrame(for: window.identifier)
        }
        return didMaximize
    }

    /// 请求目标窗口自己的关闭按钮执行 AXPress，不会强制结束应用进程。
    @discardableResult
    func close(_ window: TargetWindow) -> Bool {
        guard window.canClose,
              let rawButton = window.element.copyAttribute(kAXCloseButtonAttribute),
              CFGetTypeID(rawButton) == AXUIElementGetTypeID() else {
            return false
        }

        // Core Foundation 不提供可选转换；前面的 CFTypeID 校验保证该转换安全。
        let closeButton = rawButton as! AXUIElement
        let error = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        if error != AXError.success {
            NSLog("[MacWindowButtons] 关闭窗口失败：%d", error.rawValue)
        }
        return error == AXError.success
    }

    /// 控制条根据是否存在还原信息切换最大化/还原图标。
    func isMaximizedByThisApp(_ window: TargetWindow) -> Bool {
        stateStore.hasRestoreFrame(for: window.identifier)
    }

    /// 按钮大小改变时同步调整已由本工具最大化的窗口，始终保留恰好一行空间。
    @discardableResult
    func updateReservedTopSpace(
        for window: TargetWindow,
        reservedTopHeight: CGFloat
    ) -> Bool {
        guard stateStore.hasRestoreFrame(for: window.identifier),
              let screen = ScreenCoordinateConverter.screen(
                containingAccessibilityRect: window.frame
              ) else {
            return false
        }

        var appKitFrame = screen.visibleFrame
        appKitFrame.size.height = max(80, appKitFrame.height - reservedTopHeight)
        guard let accessibilityFrame = ScreenCoordinateConverter.accessibilityRect(
            fromAppKitRect: appKitFrame
        ) else {
            return false
        }
        return apply(frame: accessibilityFrame, to: window.element)
    }

    private func apply(frame: CGRect, to element: AXUIElement) -> Bool {
        // 先设置尺寸再设置位置，可减少部分 Chromium 应用对尺寸约束造成的偏移。
        let didSetSize = element.setSizeAttribute(kAXSizeAttribute, value: frame.size)
        let didSetPosition = element.setPointAttribute(kAXPositionAttribute, value: frame.origin)
        return didSetSize && didSetPosition
    }
}
