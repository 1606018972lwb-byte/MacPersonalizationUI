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
            case .small: 38
            case .standard: 46
            case .large: 54
            }
        }

        /// 每个按钮的真实高度；按钮会占满该矩形，整个区域都可以点击。
        var buttonHeight: CGFloat {
            switch self {
            case .small: 30
            case .standard: 35
            case .large: 42
            }
        }

        var symbolPointSize: CGFloat {
            switch self {
            case .small: 10
            case .standard: 12
            case .large: 15
            }
        }

        /// 三个按钮无缝铺满面板，不再用外边距缩小实际点击区域。
        var panelSize: CGSize {
            CGSize(width: buttonWidth * 3, height: buttonHeight)
        }
    }

    private enum Key {
        static let controlSize = "windowControlButtonSize"
        static let automaticallyHidesControls = "automaticallyHidesWindowControls"
    }

    private let defaults: UserDefaults
    private var controlSizeObservers: [UUID: (ControlSize) -> Void] = [:]
    private var autoHideObservers: [UUID: (Bool) -> Void] = [:]

    private(set) var controlSize: ControlSize
    private(set) var automaticallyHidesControls: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        controlSize = ControlSize(
            rawValue: defaults.string(forKey: Key.controlSize) ?? ""
        ) ?? .standard
        // 新安装默认开启，避免控制条长期盖住目标应用自己的标题栏工具按钮。
        automaticallyHidesControls = defaults.object(
            forKey: Key.automaticallyHidesControls
        ) as? Bool ?? true
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

    /// 保存自动隐藏选项，并让悬浮控制器立即更新显示方式。
    func setAutomaticallyHidesControls(_ shouldHide: Bool) {
        guard automaticallyHidesControls != shouldHide else {
            return
        }
        automaticallyHidesControls = shouldHide
        defaults.set(shouldHide, forKey: Key.automaticallyHidesControls)
        Array(autoHideObservers.values).forEach { observer in
            observer(shouldHide)
        }
    }

    @discardableResult
    func addAutoHideObserver(_ observer: @escaping (Bool) -> Void) -> UUID {
        let identifier = UUID()
        autoHideObservers[identifier] = observer
        return identifier
    }

    func removeAutoHideObserver(_ identifier: UUID) {
        autoHideObservers.removeValue(forKey: identifier)
    }
}
