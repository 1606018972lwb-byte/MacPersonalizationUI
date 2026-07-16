import Foundation

/// 描述悬浮窗口按钮功能当前是否工作。
///
/// 首个迭代只负责保存菜单状态；后续接入窗口监听服务后，服务应订阅
/// `onWindowButtonsEnabledChange`，而不是让菜单控制器直接依赖窗口实现。
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
