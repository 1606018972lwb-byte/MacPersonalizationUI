import CoreGraphics

/// 按窗口保存最大化之前的位置和尺寸，用于再次点击时还原。
final class WindowStateStore {
    private var restoreFrames: [WindowIdentifier: CGRect] = [:]

    func saveRestoreFrame(_ frame: CGRect, for identifier: WindowIdentifier) {
        restoreFrames[identifier] = frame
    }

    func restoreFrame(for identifier: WindowIdentifier) -> CGRect? {
        restoreFrames[identifier]
    }

    func removeRestoreFrame(for identifier: WindowIdentifier) {
        restoreFrames.removeValue(forKey: identifier)
    }

    func hasRestoreFrame(for identifier: WindowIdentifier) -> Bool {
        restoreFrames[identifier] != nil
    }
}
