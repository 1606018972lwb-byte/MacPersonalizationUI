import CoreGraphics
import Foundation

/// 使用 UserDefaults 保存用户可调节的界面设置。
final class AppSettings {
    enum ControlSize: String, CaseIterable {
        case small
        case standard
        case large

        var displayName: String {
            switch self {
            case .small: "小"
            case .standard: "标准"
            case .large: "大"
            }
        }

        var buttonWidth: CGFloat {
            switch self {
            case .small: 30
            case .standard: 36
            case .large: 44
            }
        }

        var panelHeight: CGFloat {
            switch self {
            case .small: 30
            case .standard: 34
            case .large: 42
            }
        }

        var symbolPointSize: CGFloat {
            switch self {
            case .small: 10
            case .standard: 12
            case .large: 16
            }
        }

        /// 三个按钮宽度、两个间距和左右内边距共同组成面板尺寸。
        var panelSize: CGSize {
            CGSize(width: buttonWidth * 3 + 8, height: panelHeight)
        }
    }

    private enum Key {
        static let controlSize = "windowControlButtonSize"
    }

    private let defaults: UserDefaults
    private var controlSizeObservers: [UUID: (ControlSize) -> Void] = [:]

    private(set) var controlSize: ControlSize

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        controlSize = ControlSize(
            rawValue: defaults.string(forKey: Key.controlSize) ?? ""
        ) ?? .standard
    }

    /// 保存按钮大小，并通知菜单和悬浮面板立即刷新。
    func setControlSize(_ newSize: ControlSize) {
        guard controlSize != newSize else {
            return
        }

        controlSize = newSize
        defaults.set(newSize.rawValue, forKey: Key.controlSize)
        Array(controlSizeObservers.values).forEach { observer in
            observer(newSize)
        }
    }

    /// 注册按钮大小变化监听，返回值用于在对象销毁时解除监听。
    @discardableResult
    func addControlSizeObserver(_ observer: @escaping (ControlSize) -> Void) -> UUID {
        let identifier = UUID()
        controlSizeObservers[identifier] = observer
        return identifier
    }

    /// 解除先前注册的按钮大小监听。
    func removeControlSizeObserver(_ identifier: UUID) {
        controlSizeObservers.removeValue(forKey: identifier)
    }
}
