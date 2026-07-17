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
    /// Core Graphics 窗口编号，用于把一体控制条精确排列在目标窗口下一层。
    let windowNumber: Int?
    let isMinimized: Bool
    let isFullScreen: Bool
    let canMinimize: Bool
    let canResize: Bool
    let canClose: Bool

    /// 在当前进程生命周期中区分同一应用的多个窗口。
    var identifier: WindowIdentifier {
        WindowIdentifier(processIdentifier: processIdentifier, elementHash: CFHash(element))
    }

    /// 直接从同一个 AX 窗口元素读取最新坐标，避免拖动期间重新扫描前台应用。
    func refreshingFrame() -> TargetWindow? {
        guard let position = element.pointAttribute(kAXPositionAttribute),
              let size = element.sizeAttribute(kAXSizeAttribute) else {
            return nil
        }
        return TargetWindow(
            element: element,
            processIdentifier: processIdentifier,
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            frame: CGRect(origin: position, size: size),
            windowNumber: windowNumber,
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            canMinimize: canMinimize,
            canResize: canResize,
            canClose: canClose
        )
    }
}

/// 用 PID 和 AX 元素哈希组成窗口状态存储键。
struct WindowIdentifier: Hashable {
    let processIdentifier: pid_t
    let elementHash: CFHashCode
}
