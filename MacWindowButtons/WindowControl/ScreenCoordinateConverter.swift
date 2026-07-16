import AppKit

/// 在 Accessibility 的左上角坐标系和 AppKit 的左下角坐标系之间转换。
enum ScreenCoordinateConverter {
    /// 将 AX/Quartz 全局窗口坐标转换为 AppKit 屏幕坐标。
    static func appKitRect(fromAccessibilityRect rect: CGRect) -> CGRect? {
        guard let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        return CGRect(
            x: rect.minX,
            y: primaryScreen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// 将 AppKit 屏幕坐标转换为 AX/Quartz 全局坐标。
    static func accessibilityRect(fromAppKitRect rect: CGRect) -> CGRect? {
        guard let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        return CGRect(
            x: rect.minX,
            y: primaryScreen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// 找到与目标窗口重叠面积最大的显示器，支持窗口跨屏时选择主要所在屏幕。
    static func screen(containingAccessibilityRect rect: CGRect) -> NSScreen? {
        guard let appKitRect = appKitRect(fromAccessibilityRect: rect) else {
            return nil
        }

        return NSScreen.screens.max { first, second in
            intersectionArea(first.frame, appKitRect) < intersectionArea(second.frame, appKitRect)
        }
    }

    private static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else {
            return 0
        }
        return intersection.width * intersection.height
    }
}
