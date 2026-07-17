import AppKit
import ApplicationServices

/// 读取当前前台应用及其焦点窗口。
final class AccessibilityWindowManager {
    private let permissionManager: AccessibilityPermissionManager
    // AXFullScreen 在部分 SDK 中未导出 Swift 常量，但属性名是稳定的公开 AX 名称。
    private let fullScreenAttribute = "AXFullScreen"
    private let persistentWindowSubroles: Set<String> = [
        "AXStandardWindow",
        "AXDialog",
        "AXSystemDialog"
    ]
    private let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.brave.Browser",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Canary",
        "com.microsoft.edgemac.Dev",
        "company.thebrowser.Browser",
        "org.chromium.Chromium",
        "org.mozilla.firefox",
        "com.vivaldi.Vivaldi"
    ]
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
        guard permissionManager.isTrusted else {
            return nil
        }

        // UIElement/附件应用显示设置窗口后，NSWorkspace 可能仍把之前的普通应用
        // 报告为 frontmost。只要本应用处于活动状态且确实有 Key Window，就优先
        // 读取自身焦点窗口，避免控制条错误绑定到后方 Finder 或浏览器。
        if NSApp.isActive,
           NSApp.keyWindow?.isVisible == true,
           let ownApplication = NSRunningApplication(
                processIdentifier: ProcessInfo.processInfo.processIdentifier
           ),
           let ownWindow = focusedWindow(in: ownApplication) {
            return ownWindow
        }

        guard let application = NSWorkspace.shared.frontmostApplication,
              isEligible(application) else {
            return nil
        }

        return focusedWindow(in: application)
    }

    private func focusedWindow(in application: NSRunningApplication) -> TargetWindow? {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        if let focusedWindow = targetWindow(
            from: applicationElement.copyAttribute(kAXFocusedWindowAttribute),
            application: application
        ) {
            return focusedWindow
        }

        // 浏览器扩展弹窗会暂时成为 AXFocusedWindow，但浏览器进程本身仍是前台应用。
        // 插件窗口被分类器排除后，继续查找 AXMainWindow，让控制条留在浏览器主窗口。
        guard browserBundleIdentifiers.contains(application.bundleIdentifier ?? "") else {
            return nil
        }
        if let mainWindow = targetWindow(
            from: applicationElement.copyAttribute(kAXMainWindowAttribute),
            application: application
        ) {
            return mainWindow
        }

        // 少数 Chromium 版本在插件打开时不提供 AXMainWindow。此时从同一进程的
        // 可控制标准窗口中选择面积最大的一个，避免控制条随插件弹窗一起消失。
        guard let rawWindows = applicationElement.copyAttribute(kAXWindowsAttribute),
              let windows = rawWindows as? [AXUIElement] else {
            return nil
        }
        return windows
            .compactMap { makeTargetWindow(from: $0, application: application) }
            .max { first, second in
                first.frame.width * first.frame.height
                    < second.frame.width * second.frame.height
            }
    }

    private func targetWindow(
        from rawWindow: CFTypeRef?,
        application: NSRunningApplication
    ) -> TargetWindow? {
        guard let rawWindow,
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            return nil
        }
        // Core Foundation 不提供可选转换；前面的 CFTypeID 校验保证该转换安全。
        return makeTargetWindow(
            from: rawWindow as! AXUIElement,
            application: application
        )
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
        let isOwnApplication = application.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
        return (application.activationPolicy == .regular || isOwnApplication)
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

        let subrole = window.stringAttribute(kAXSubroleAttribute) ?? ""
        let closeButton = window.copyAttribute(kAXCloseButtonAttribute)
        let canClose = closeButton.map {
            CFGetTypeID($0) == AXUIElementGetTypeID()
        } ?? false
        let canMinimize = window.isAttributeSettable(kAXMinimizedAttribute)
        let canResize = window.isAttributeSettable(kAXPositionAttribute)
            && window.isAttributeSettable(kAXSizeAttribute)

        // 浏览器扩展经常把插件气泡报告为 AXDialog。浏览器中只接受真正的
        // AXStandardWindow；浏览器设置页如果位于标签页内，仍属于这个主窗口。
        if browserBundleIdentifiers.contains(application.bundleIdentifier ?? ""),
           subrole != "AXStandardWindow" {
            return nil
        }

        // 浏览器扩展弹窗、菜单面板和气泡虽然有时也报告 AXWindow，但通常使用
        // AXFloatingWindow/AXUnknown 子角色，且没有原生关闭、最小化或缩放能力。
        // 普通偏好设置窗口仍是 AXStandardWindow/AXDialog，并至少有关闭按钮。
        guard persistentWindowSubroles.contains(subrole),
              canClose || canMinimize || canResize else {
            return nil
        }

        return TargetWindow(
            element: window,
            processIdentifier: application.processIdentifier,
            applicationName: application.localizedName ?? "未知应用",
            bundleIdentifier: application.bundleIdentifier ?? "",
            title: window.stringAttribute(kAXTitleAttribute) ?? "",
            frame: CGRect(origin: position, size: size),
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            canMinimize: canMinimize,
            canResize: canResize,
            canClose: canClose
        )
    }
}
