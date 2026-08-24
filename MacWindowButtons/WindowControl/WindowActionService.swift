import AppKit
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

    /// 悬浮样式要求目标窗口顶部始终留出完整控制条高度。
    ///
    /// 普通窗口优先整体下移；窗口已经占满可见屏幕时同时缩短高度，避免把底部
    /// 推出屏幕。只有确实修改成功时返回 true，调用方随后重新读取最终坐标。
    @discardableResult
    func ensureTopClearance(for window: TargetWindow, clearance: CGFloat) -> Bool {
        guard clearance > 0,
              let screen = ScreenCoordinateConverter.screen(
                containingAccessibilityRect: window.frame
              ),
              let currentFrame = ScreenCoordinateConverter.appKitRect(
                fromAccessibilityRect: window.frame
              ) else {
            return false
        }

        let highestAllowedWindowTop = screen.visibleFrame.maxY - clearance
        let overflow = currentFrame.maxY - highestAllowedWindowTop
        guard overflow > 0.5 else {
            return false
        }

        var adjustedFrame = currentFrame
        adjustedFrame.origin.y -= overflow
        if adjustedFrame.minY < screen.visibleFrame.minY,
           window.canResize {
            let bottomOverflow = screen.visibleFrame.minY - adjustedFrame.minY
            adjustedFrame.origin.y = screen.visibleFrame.minY
            adjustedFrame.size.height = max(80, adjustedFrame.height - bottomOverflow)
        }

        guard let accessibilityFrame = ScreenCoordinateConverter.accessibilityRect(
            fromAppKitRect: adjustedFrame
        ) else {
            return false
        }
        if adjustedFrame.size != currentFrame.size {
            return apply(frame: accessibilityFrame, to: window.element)
        }
        return move(window, to: accessibilityFrame.origin)
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

        guard let maximizeFrame = maximizedFrame(
            for: window,
            reservedTopHeight: reservedTopHeight
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
              let accessibilityFrame = maximizedFrame(
                for: window,
                reservedTopHeight: reservedTopHeight
              ) else {
            return false
        }
        return apply(frame: accessibilityFrame, to: window.element)
    }

    /// Electron 等应用偶尔会接受第一次 AX 写入，却在下一轮布局中恢复部分尺寸。
    /// 最大化动作完成后重新读取实际 frame，仅在有偏差时执行一次精确校正。
    @discardableResult
    func correctMaximizedFrameIfNeeded(
        for window: TargetWindow,
        reservedTopHeight: CGFloat
    ) -> Bool {
        guard stateStore.hasRestoreFrame(for: window.identifier),
              let targetFrame = maximizedFrame(
                for: window,
                reservedTopHeight: reservedTopHeight
              ) else {
            return false
        }
        guard !window.frame.isApproximatelyEqual(to: targetFrame) else {
            return true
        }
        return apply(frame: targetFrame, to: window.element)
    }

    private func maximizedFrame(
        for window: TargetWindow,
        reservedTopHeight: CGFloat
    ) -> CGRect? {
        guard let screen = ScreenCoordinateConverter.screen(
            containingAccessibilityRect: window.frame
        ) else {
            return nil
        }

        // visibleFrame 是当前显示器扣除菜单栏和 Dock 后的真实可用区域。
        // AppKit 使用左下角坐标，保持 minY 不变并缩短高度，会把预留行放在顶部。
        var appKitFrame = screen.visibleFrame
        appKitFrame.size.height = max(
            80,
            appKitFrame.height - reservedTopHeight
        )
        return ScreenCoordinateConverter.accessibilityRect(fromAppKitRect: appKitFrame)
    }

    private func apply(frame: CGRect, to element: AXUIElement) -> Bool {
        // 先把窗口左上角放进目标屏幕，再设置完整尺寸。Electron/Chromium 会根据
        // 设置尺寸时所在的屏幕施加约束，因此最后再写一次位置消除布局舍入偏差。
        let didSetInitialPosition = element.setPointAttribute(
            kAXPositionAttribute,
            value: frame.origin
        )
        let didSetSize = element.setSizeAttribute(kAXSizeAttribute, value: frame.size)
        let didSetFinalPosition = element.setPointAttribute(
            kAXPositionAttribute,
            value: frame.origin
        )
        return didSetSize && (didSetInitialPosition || didSetFinalPosition)
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
