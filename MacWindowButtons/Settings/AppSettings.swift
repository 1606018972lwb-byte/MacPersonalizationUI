import CoreGraphics
import Foundation

/// 使用 UserDefaults 保存用户可调节的界面设置。
final class AppSettings {
    enum ControlAppearance: String, CaseIterable {
        case floating
        case integrated

        var displayName: String {
            switch self {
            case .floating: "当前悬浮样式"
            case .integrated: "与窗口一体"
            }
        }

        /// 一体样式稍微覆盖原窗口顶部，填平原生窗口圆角留下的视觉缺口。
        var windowOverlap: CGFloat {
            switch self {
            case .floating: 0
            case .integrated: 5
            }
        }
    }

    enum UpdateInterval: String, CaseIterable {
        case daily
        case weekly
        case monthly

        var displayName: String {
            switch self {
            case .daily: "每天"
            case .weekly: "每 7 天"
            case .monthly: "每 30 天"
            }
        }

        var timeInterval: TimeInterval {
            switch self {
            case .daily: 24 * 60 * 60
            case .weekly: 7 * 24 * 60 * 60
            case .monthly: 30 * 24 * 60 * 60
            }
        }
    }

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
        static let controlAppearance = "windowControlAppearance"
        static let checksForUpdates = "checksForUpdates"
        static let updateInterval = "updateCheckInterval"
        static let automaticallyInstallsUpdates = "automaticallyInstallsUpdates"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
    }

    private let defaults: UserDefaults
    private var controlSizeObservers: [UUID: (ControlSize) -> Void] = [:]
    private var controlAppearanceObservers: [UUID: (ControlAppearance) -> Void] = [:]

    private(set) var controlSize: ControlSize
    private(set) var controlAppearance: ControlAppearance
    private(set) var checksForUpdates: Bool
    private(set) var updateInterval: UpdateInterval
    private(set) var automaticallyInstallsUpdates: Bool
    private(set) var lastUpdateCheckDate: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        controlSize = ControlSize(
            rawValue: defaults.string(forKey: Key.controlSize) ?? ""
        ) ?? .standard
        // 保留现有用户已经习惯的悬浮样式作为默认值；一体样式由用户主动选择。
        controlAppearance = ControlAppearance(
            rawValue: defaults.string(forKey: Key.controlAppearance) ?? ""
        ) ?? .floating
        checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true
        updateInterval = UpdateInterval(
            rawValue: defaults.string(forKey: Key.updateInterval) ?? ""
        ) ?? .weekly
        // 新安装默认启用安全自动更新；如果用户已经主动修改过该选项，继续尊重
        // 已保存的值。关闭更新提醒时自动更新也必须保持关闭，避免后台继续联网。
        let savedAutomaticUpdate = defaults.object(
            forKey: Key.automaticallyInstallsUpdates
        ) as? Bool
        automaticallyInstallsUpdates = checksForUpdates
            && (savedAutomaticUpdate ?? true)
        lastUpdateCheckDate = defaults.object(forKey: Key.lastUpdateCheckDate) as? Date
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

    func setControlAppearance(_ newAppearance: ControlAppearance) {
        guard controlAppearance != newAppearance else {
            return
        }
        controlAppearance = newAppearance
        defaults.set(newAppearance.rawValue, forKey: Key.controlAppearance)
        Array(controlAppearanceObservers.values).forEach { observer in
            observer(newAppearance)
        }
    }

    @discardableResult
    func addControlAppearanceObserver(
        _ observer: @escaping (ControlAppearance) -> Void
    ) -> UUID {
        let identifier = UUID()
        controlAppearanceObservers[identifier] = observer
        return identifier
    }

    func removeControlAppearanceObserver(_ identifier: UUID) {
        controlAppearanceObservers.removeValue(forKey: identifier)
    }

    func setChecksForUpdates(_ enabled: Bool) {
        checksForUpdates = enabled
        defaults.set(enabled, forKey: Key.checksForUpdates)
        if !enabled {
            setAutomaticallyInstallsUpdates(false)
        }
    }

    func setUpdateInterval(_ interval: UpdateInterval) {
        updateInterval = interval
        defaults.set(interval.rawValue, forKey: Key.updateInterval)
    }

    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
        automaticallyInstallsUpdates = enabled
        defaults.set(enabled, forKey: Key.automaticallyInstallsUpdates)
    }

    func markUpdateCheckCompleted(at date: Date = Date()) {
        lastUpdateCheckDate = date
        defaults.set(date, forKey: Key.lastUpdateCheckDate)
    }

}
