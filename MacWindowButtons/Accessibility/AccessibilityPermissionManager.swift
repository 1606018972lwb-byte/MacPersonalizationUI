import AppKit
import ApplicationServices

/// 管理辅助功能权限检查、系统授权提示和设置跳转。
final class AccessibilityPermissionManager {
    /// 当前进程是否已获得控制其他应用窗口所需的辅助功能权限。
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 用户点击“立即授权”时请求权限并显示清晰说明。
    func requestPermissionFromUser() {
        if isTrusted {
            showPermissionStatus()
            return
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        showPermissionAlert(
            message: "需要辅助功能权限",
            detail: "MacWindowButtons 必须获得辅助功能权限，才能读取微信等应用的窗口并在右上角显示控制按钮。授权后请返回应用，按钮会自动出现。"
        )
    }

    /// 显示当前授权状态；该方法只在用户主动点击菜单时调用。
    func showPermissionStatus() {
        if isTrusted {
            showInformationAlert(
                message: "辅助功能权限已开启",
                detail: "窗口读取与右侧控制按钮可以正常工作。"
            )
        } else {
            showPermissionAlert(
                message: "辅助功能权限未开启",
                detail: "请在“系统设置 → 隐私与安全性 → 辅助功能”中开启 MacWindowButtons。"
            )
        }
    }

    /// 打开系统设置的“辅助功能”隐私页面。
    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            NSLog("[MacWindowButtons] 无法创建辅助功能设置页面 URL")
            return
        }

        if !NSWorkspace.shared.open(url) {
            NSLog("[MacWindowButtons] 无法打开辅助功能设置页面")
        }
    }

    private func showPermissionAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }

    private func showInformationAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
