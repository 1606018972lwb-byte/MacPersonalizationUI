import AppKit
import ApplicationServices

/// 管理辅助功能权限检查、系统授权提示和设置跳转。
final class AccessibilityPermissionManager {
    private var permissionResetTask: Process?

    /// 当前进程是否已获得控制其他应用窗口所需的辅助功能权限。
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 只调用 macOS 原生授权提示，不再叠加应用自己的模态弹窗。
    func requestPermissionFromUser() {
        if isTrusted {
            showPermissionStatus()
            return
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 清除与旧临时签名绑定的失效权限记录，再请求当前版本的系统权限。
    ///
    /// 测试包升级后，系统设置可能保留一个看似开启、但仍绑定旧 cdhash 的条目。
    /// `tccutil reset` 只重置本应用的辅助功能权限，不影响其他应用。
    func repairPermissionFromUser(completion: @escaping (String?) -> Void) {
        let resetTask = Process()
        resetTask.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        resetTask.arguments = ["reset", "Accessibility", "com.lwb.MacWindowButtons"]
        resetTask.terminationHandler = { [weak self] task in
            DispatchQueue.main.async {
                self?.permissionResetTask = nil
                guard task.terminationStatus == 0 else {
                    completion("系统无法重置旧权限记录，请在辅助功能列表中删除应用后重新添加。")
                    return
                }
                self?.requestPermissionFromUser()
                completion(nil)
            }
        }

        do {
            permissionResetTask = resetTask
            try resetTask.run()
        } catch {
            permissionResetTask = nil
            completion("无法启动权限修复工具：\(error.localizedDescription)")
        }
    }

    /// 显示当前授权状态；该方法只在用户主动点击菜单时调用。
    func showPermissionStatus() {
        if isTrusted {
            showInformationAlert(
                message: "辅助功能权限已开启",
                detail: "窗口读取与右侧控制按钮可以正常工作。"
            )
        } else {
            requestPermissionFromUser()
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

    private func showInformationAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
