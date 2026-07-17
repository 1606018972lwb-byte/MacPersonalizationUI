import AppKit
import CoreGraphics
import Foundation

/// 可持久化的物理键盘组合，不受当前输入法字符布局影响。
struct GlobalKeyboardShortcut: Equatable {
    /// `nil` 表示快捷键只由一个或多个修饰键组成。
    let keyCode: UInt32?
    let modifierFlags: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    var displayName: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        if let keyCode {
            text += Self.keyName(for: keyCode)
        }
        return text
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "⎋",
            115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        if let name = names[keyCode] {
            return name
        }
        let keyNames: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z",
            7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
            14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
            26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
            32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`"
        ]
        return keyNames[keyCode] ?? "键 \(keyCode)"
    }
}

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
        static let modifierOnlyKeyCode = UInt32.max
        static let controlSize = "windowControlButtonSize"
        static let controlAppearance = "windowControlAppearance"
        static let launchesSilently = "launchesSilently"
        static let checksForUpdates = "checksForUpdates"
        static let updateInterval = "updateCheckInterval"
        static let automaticallyInstallsUpdates = "automaticallyInstallsUpdates"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
        static let deleteMovesFilesToTrash = "deleteMovesFilesToTrash"
        static let inputMethodShortcutEnabled = "inputMethodShortcutEnabled"
        static let inputMethodShortcutKeyCode = "inputMethodShortcutKeyCode"
        static let inputMethodShortcutModifiers = "inputMethodShortcutModifiers"
        static let chineseEnglishShortcutEnabled = "chineseEnglishShortcutEnabled"
        static let chineseEnglishShortcutKeyCode = "chineseEnglishShortcutKeyCode"
        static let chineseEnglishShortcutModifiers = "chineseEnglishShortcutModifiers"
    }

    private let defaults: UserDefaults
    private var controlSizeObservers: [UUID: (ControlSize) -> Void] = [:]
    private var controlAppearanceObservers: [UUID: (ControlAppearance) -> Void] = [:]
    private var deleteShortcutObservers: [UUID: (Bool) -> Void] = [:]

    private(set) var controlSize: ControlSize
    private(set) var controlAppearance: ControlAppearance
    private(set) var launchesSilently: Bool
    private(set) var checksForUpdates: Bool
    private(set) var updateInterval: UpdateInterval
    private(set) var automaticallyInstallsUpdates: Bool
    private(set) var lastUpdateCheckDate: Date?
    private(set) var deleteMovesFilesToTrash: Bool
    private(set) var isInputMethodShortcutEnabled: Bool
    private(set) var inputMethodShortcut: GlobalKeyboardShortcut?
    private(set) var isChineseEnglishShortcutEnabled: Bool
    private(set) var chineseEnglishShortcut: GlobalKeyboardShortcut?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        controlSize = ControlSize(
            rawValue: defaults.string(forKey: Key.controlSize) ?? ""
        ) ?? .standard
        // 保留现有用户已经习惯的悬浮样式作为默认值；一体样式由用户主动选择。
        controlAppearance = ControlAppearance(
            rawValue: defaults.string(forKey: Key.controlAppearance) ?? ""
        ) ?? .floating
        // 菜单栏工具默认在后台静默启动；设置窗口由用户点击菜单栏图标或
        // 再次启动应用时主动打开，避免登录后打断当前工作。
        launchesSilently = defaults.object(forKey: Key.launchesSilently) as? Bool ?? true
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
        // Delete 是具有破坏性的全局操作，新安装必须由用户明确勾选后才启用。
        deleteMovesFilesToTrash = defaults.object(
            forKey: Key.deleteMovesFilesToTrash
        ) as? Bool ?? false
        isInputMethodShortcutEnabled = defaults.object(
            forKey: Key.inputMethodShortcutEnabled
        ) as? Bool ?? false
        if let keyCode = defaults.object(
            forKey: Key.inputMethodShortcutKeyCode
        ) as? NSNumber,
           let modifiers = defaults.object(
            forKey: Key.inputMethodShortcutModifiers
           ) as? NSNumber {
            inputMethodShortcut = GlobalKeyboardShortcut(
                keyCode: keyCode.uint32Value == Key.modifierOnlyKeyCode
                    ? nil
                    : keyCode.uint32Value,
                modifierFlags: modifiers.uintValue
            )
        } else {
            inputMethodShortcut = nil
        }
        isChineseEnglishShortcutEnabled = defaults.object(
            forKey: Key.chineseEnglishShortcutEnabled
        ) as? Bool ?? false
        if let keyCode = defaults.object(
            forKey: Key.chineseEnglishShortcutKeyCode
        ) as? NSNumber,
           let modifiers = defaults.object(
            forKey: Key.chineseEnglishShortcutModifiers
           ) as? NSNumber {
            chineseEnglishShortcut = GlobalKeyboardShortcut(
                keyCode: keyCode.uint32Value == Key.modifierOnlyKeyCode
                    ? nil
                    : keyCode.uint32Value,
                modifierFlags: modifiers.uintValue
            )
        } else {
            chineseEnglishShortcut = nil
        }
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

    func setLaunchesSilently(_ enabled: Bool) {
        launchesSilently = enabled
        defaults.set(enabled, forKey: Key.launchesSilently)
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

    /// 保存 Finder Delete 快捷键状态，并通知全局键盘监听立即启用或停止。
    func setDeleteMovesFilesToTrash(_ enabled: Bool) {
        guard deleteMovesFilesToTrash != enabled else {
            return
        }
        deleteMovesFilesToTrash = enabled
        defaults.set(enabled, forKey: Key.deleteMovesFilesToTrash)
        Array(deleteShortcutObservers.values).forEach { observer in
            observer(enabled)
        }
    }

    @discardableResult
    func addDeleteShortcutObserver(_ observer: @escaping (Bool) -> Void) -> UUID {
        let identifier = UUID()
        deleteShortcutObservers[identifier] = observer
        return identifier
    }

    func removeDeleteShortcutObserver(_ identifier: UUID) {
        deleteShortcutObservers.removeValue(forKey: identifier)
    }

    func setInputMethodShortcut(_ shortcut: GlobalKeyboardShortcut) {
        inputMethodShortcut = shortcut
        defaults.set(
            shortcut.keyCode ?? Key.modifierOnlyKeyCode,
            forKey: Key.inputMethodShortcutKeyCode
        )
        defaults.set(shortcut.modifierFlags, forKey: Key.inputMethodShortcutModifiers)
    }

    func setInputMethodShortcutEnabled(_ enabled: Bool) {
        isInputMethodShortcutEnabled = enabled
        defaults.set(enabled, forKey: Key.inputMethodShortcutEnabled)
    }

    func setChineseEnglishShortcut(_ shortcut: GlobalKeyboardShortcut) {
        chineseEnglishShortcut = shortcut
        defaults.set(
            shortcut.keyCode ?? Key.modifierOnlyKeyCode,
            forKey: Key.chineseEnglishShortcutKeyCode
        )
        defaults.set(shortcut.modifierFlags, forKey: Key.chineseEnglishShortcutModifiers)
    }

    func setChineseEnglishShortcutEnabled(_ enabled: Bool) {
        isChineseEnglishShortcutEnabled = enabled
        defaults.set(enabled, forKey: Key.chineseEnglishShortcutEnabled)
    }

}
