import ApplicationServices
import CoreGraphics

/// 当前可由 Accessibility API 控制的外部应用窗口快照。
struct TargetWindow {
    let element: AXUIElement
    let processIdentifier: pid_t
    let applicationName: String
    let bundleIdentifier: String
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    let isFullScreen: Bool
    let canMinimize: Bool
    let canResize: Bool
    let canClose: Bool

    /// 在当前进程生命周期中区分同一应用的多个窗口。
    var identifier: WindowIdentifier {
        WindowIdentifier(processIdentifier: processIdentifier, elementHash: CFHash(element))
    }
}

/// 用 PID 和 AX 元素哈希组成窗口状态存储键。
struct WindowIdentifier: Hashable {
    let processIdentifier: pid_t
    let elementHash: CFHashCode
}
