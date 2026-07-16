import AppKit
import ApplicationServices

/// 读取当前前台应用及其焦点窗口。
final class AccessibilityWindowManager {
    private let permissionManager: AccessibilityPermissionManager
    // AXFullScreen 在部分 SDK 中未导出 Swift 常量，但属性名是稳定的公开 AX 名称。
    private let fullScreenAttribute = "AXFullScreen"
    private let excludedBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui"
    ]

    init(permissionManager: AccessibilityPermissionManager) {
        self.permissionManager = permissionManager
    }

    /// 返回当前焦点标准窗口；无权限、全屏、最小化或无有效窗口时返回 nil。
    func focusedWindow() -> TargetWindow? {
        guard permissionManager.isTrusted,
              let application = NSWorkspace.shared.frontmostApplication,
              isEligible(application) else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let rawWindow = applicationElement.copyAttribute(kAXFocusedWindowAttribute),
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            return nil
        }

        // Core Foundation 不提供可选转换；前面的 CFTypeID 校验保证该转换安全。
        let window = rawWindow as! AXUIElement
        return makeTargetWindow(from: window, application: application)
    }

    /// 扫描所有正在运行的普通应用，返回当前可控制的非最小化标准窗口。
    func allControllableWindows() -> [TargetWindow] {
        guard permissionManager.isTrusted else {
            return []
        }

        return NSWorkspace.shared.runningApplications
            .filter(isEligible)
            .flatMap { application -> [TargetWindow] in
                let applicationElement = AXUIElementCreateApplication(
                    application.processIdentifier
                )
                guard let rawWindows = applicationElement.copyAttribute(kAXWindowsAttribute),
                      let windows = rawWindows as? [AXUIElement] else {
                    return []
                }
                return windows.compactMap { window in
                    makeTargetWindow(from: window, application: application)
                }
            }
    }

    private func isEligible(_ application: NSRunningApplication) -> Bool {
        application.activationPolicy == .regular
            && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && application.bundleIdentifier != Bundle.main.bundleIdentifier
            && !excludedBundleIdentifiers.contains(application.bundleIdentifier ?? "")
            && !application.isTerminated
    }

    private func makeTargetWindow(
        from window: AXUIElement,
        application: NSRunningApplication
    ) -> TargetWindow? {
        guard window.stringAttribute(kAXRoleAttribute) == kAXWindowRole as String,
              let position = window.pointAttribute(kAXPositionAttribute),
              let size = window.sizeAttribute(kAXSizeAttribute),
              size.width >= 180,
              size.height >= 80 else {
            return nil
        }

        let isMinimized = window.boolAttribute(kAXMinimizedAttribute) ?? false
        let isFullScreen = window.boolAttribute(fullScreenAttribute) ?? false
        guard !isMinimized, !isFullScreen else {
            return nil
        }

        let closeButton = window.copyAttribute(kAXCloseButtonAttribute)
        return TargetWindow(
            element: window,
            processIdentifier: application.processIdentifier,
            applicationName: application.localizedName ?? "未知应用",
            bundleIdentifier: application.bundleIdentifier ?? "",
            title: window.stringAttribute(kAXTitleAttribute) ?? "",
            frame: CGRect(origin: position, size: size),
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            canMinimize: window.isAttributeSettable(kAXMinimizedAttribute),
            canResize: window.isAttributeSettable(kAXPositionAttribute)
                && window.isAttributeSettable(kAXSizeAttribute),
            canClose: closeButton.map { CFGetTypeID($0) == AXUIElementGetTypeID() } ?? false
        )
    }
}
