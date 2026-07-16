import Foundation

/// 描述悬浮窗口按钮功能当前是否工作。
///
/// 状态由菜单修改，悬浮面板读取该值决定显示或隐藏，避免 UI 组件互相依赖。
final class ApplicationState {
    /// 窗口按钮状态改变时由上层注入的回调。
    var onWindowButtonsEnabledChange: ((Bool) -> Void)?

    /// 当前是否允许显示和使用窗口按钮。
    private(set) var areWindowButtonsEnabled = true

    /// 启用窗口按钮，并在状态真正变化时通知订阅者。
    func enableWindowButtons() {
        setWindowButtonsEnabled(true)
    }

    /// 暂停窗口按钮，并在状态真正变化时通知订阅者。
    func pauseWindowButtons() {
        setWindowButtonsEnabled(false)
    }

    private func setWindowButtonsEnabled(_ isEnabled: Bool) {
        guard areWindowButtonsEnabled != isEnabled else {
            return
        }

        areWindowButtonsEnabled = isEnabled
        onWindowButtonsEnabledChange?(isEnabled)
    }
}
