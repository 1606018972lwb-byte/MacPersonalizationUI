import AppKit
import ApplicationServices
import Carbon

/// 管理仅在文本输入控件中生效的输入源快捷键。
final class InputMethodShortcutController {
    enum Action: UInt32, CaseIterable {
        case nextInputMethod = 1
        case toggleChineseEnglish = 2
    }

    enum RegistrationResult {
        case success
        case missingShortcut
        case conflict
        case failed(String)
    }

    private let appSettings: AppSettings
    private var localEventMonitors: [Any] = []
    private var modifierOnlyCandidateAction: Action?
    private var modifierOnlyCandidateIsInvalid = false
    private var statusTexts: [Action: String] = [:]
    private var lastLatinInputSourceID: String?
    private var lastChineseInputSourceID: String?
    var onStateChange: (() -> Void)?

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        Action.allCases.forEach { statusTexts[$0] = "默认关闭，请先录入快捷键。" }
    }

    func start() {
        installLocalShortcutMonitorsIfNeeded()
        for action in Action.allCases {
            guard isEnabled(action) else {
                updateStatus("已关闭。", for: action)
                continue
            }
            switch setEnabled(true, for: action) {
            case .success:
                break
            case .conflict:
                saveEnabled(false, for: action)
                updateStatus("已保存的快捷键发生冲突，已自动关闭。", for: action)
            case .missingShortcut:
                saveEnabled(false, for: action)
                updateStatus("尚未设置快捷键，已自动关闭。", for: action)
            case let .failed(message):
                saveEnabled(false, for: action)
                updateStatus(message, for: action)
            }
        }
    }

    func stop() {
        localEventMonitors.forEach(NSEvent.removeMonitor)
        localEventMonitors.removeAll()
    }

    func statusText(for action: Action) -> String {
        statusTexts[action] ?? ""
    }

    /// 局部快捷键不会占用系统全局热键；这里只拒绝两个输入源功能使用相同组合。
    func updateShortcut(
        _ shortcut: GlobalKeyboardShortcut,
        for action: Action
    ) -> RegistrationResult {
        dispatchPrecondition(condition: .onQueue(.main))
        if shortcut == savedShortcut(for: action) {
            return .success
        }

        if Action.allCases.contains(where: {
            $0 != action && savedShortcut(for: $0) == shortcut
        }) {
            updateStatus("快捷键 \(shortcut.displayName) 与本页另一项设置重复。", for: action)
            return .conflict
        }

        saveShortcut(shortcut, for: action)
        resetModifierOnlyCandidate()
        updateStatus(
            isEnabled(action)
                ? localEnabledStatus(for: shortcut)
                : "快捷键可用，勾选后仅在输入框生效：\(shortcut.displayName)",
            for: action
        )
        return .success
    }

    func setEnabled(_ enabled: Bool, for action: Action) -> RegistrationResult {
        dispatchPrecondition(condition: .onQueue(.main))
        guard enabled else {
            saveEnabled(false, for: action)
            resetModifierOnlyCandidate()
            updateStatus("已关闭。", for: action)
            return .success
        }
        guard let shortcut = savedShortcut(for: action) else {
            updateStatus("请先点击输入框并按下一个组合键。", for: action)
            return .missingShortcut
        }
        saveEnabled(true, for: action)
        updateStatus(localEnabledStatus(for: shortcut), for: action)
        return .success
    }

    /// 事件可以来自任意应用，但只有辅助功能焦点确认位于文本输入控件时才执行。
    /// 监听器不拦截原事件，因此普通窗口区域和其他应用快捷键行为保持不变。
    private func installLocalShortcutMonitorsIfNeeded() {
        guard localEventMonitors.isEmpty else {
            return
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown],
            handler: { [weak self] event in
                self?.handleLocalShortcutEvent(event)
            }
        ) {
            localEventMonitors.append(monitor)
        }
    }

    private func handleLocalShortcutEvent(_ event: NSEvent) {
        dispatchPrecondition(condition: .onQueue(.main))
        let enabledShortcuts = Action.allCases.compactMap { action -> (
            action: Action,
            shortcut: GlobalKeyboardShortcut
        )? in
            guard isEnabled(action), let shortcut = savedShortcut(for: action) else {
                return nil
            }
            return (action, shortcut)
        }
        guard !enabledShortcuts.isEmpty else {
            resetModifierOnlyCandidate()
            return
        }

        if event.type == .keyDown {
            // 任意普通键都会取消正在等待释放的纯修饰键组合，避免
            // Command-Shift-T 等三键快捷键被误判成 Command-Shift。
            modifierOnlyCandidateIsInvalid = true
            guard !event.isARepeat else {
                return
            }
            let eventModifiers = relevantModifiers(event.modifierFlags)
            guard let match = enabledShortcuts.first(where: {
                $0.shortcut.keyCode == UInt32(event.keyCode)
                    && $0.shortcut.modifiers == eventModifiers
            }),
                  isFocusedElementTextInput() else {
                return
            }
            perform(match.action)
            return
        }

        guard event.type == .flagsChanged else {
            return
        }
        let modifierOnlyShortcuts = enabledShortcuts.filter {
            $0.shortcut.keyCode == nil
        }
        handleModifierOnlyShortcut(
            currentModifiers: relevantModifiers(event.modifierFlags),
            shortcuts: modifierOnlyShortcuts
        )
    }

    private func handleModifierOnlyShortcut(
        currentModifiers: NSEvent.ModifierFlags,
        shortcuts: [(action: Action, shortcut: GlobalKeyboardShortcut)]
    ) {
        guard !shortcuts.isEmpty else {
            resetModifierOnlyCandidate()
            return
        }
        if let match = shortcuts.first(where: {
            !$0.shortcut.modifiers.isEmpty
                && $0.shortcut.modifiers == currentModifiers
        }) {
            if let candidateAction = modifierOnlyCandidateAction,
               candidateAction != match.action,
               let candidateShortcut = savedShortcut(for: candidateAction) {
                // 从单修饰键继续按到已配置的组合修饰键时，优先采用更完整
                // 的组合；释放组合中的某个键时则不能降级触发单修饰键。
                if currentModifiers.rawValue.nonzeroBitCount
                    > candidateShortcut.modifiers.rawValue.nonzeroBitCount {
                    modifierOnlyCandidateAction = match.action
                    modifierOnlyCandidateIsInvalid = false
                }
            } else if modifierOnlyCandidateAction == nil {
                modifierOnlyCandidateAction = match.action
                modifierOnlyCandidateIsInvalid = false
            }
            return
        }
        guard let candidateAction = modifierOnlyCandidateAction,
              let candidateShortcut = savedShortcut(for: candidateAction) else {
            return
        }

        let containsUnexpectedModifier = currentModifiers.rawValue
            & ~candidateShortcut.modifiers.rawValue != 0
        if containsUnexpectedModifier {
            modifierOnlyCandidateIsInvalid = true
        }
        guard currentModifiers.isEmpty else {
            return
        }

        let shouldPerform = !modifierOnlyCandidateIsInvalid
            && isFocusedElementTextInput()
        resetModifierOnlyCandidate()
        if shouldPerform {
            perform(candidateAction)
        }
    }

    private func relevantModifiers(
        _ flags: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift])
    }

    /// 通过当前前台进程的 AXFocusedUIElement 判断光标是否位于可编辑文本区域。
    /// 常规文本框、搜索/地址栏、多行编辑器及网页可编辑文本均会报告这些角色。
    private func isFocusedElementTextInput() -> Bool {
        guard AXIsProcessTrusted(),
              let application = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        guard let rawElement = applicationElement.copyAttribute(
            kAXFocusedUIElementAttribute
        ), CFGetTypeID(rawElement) == AXUIElementGetTypeID() else {
            return false
        }
        let element = rawElement as! AXUIElement
        let role = element.stringAttribute(kAXRoleAttribute) ?? ""
        let textRoles: Set<String> = [
            "AXTextField",
            "AXTextArea",
            "AXComboBox"
        ]
        if textRoles.contains(role) {
            return true
        }
        let subrole = element.stringAttribute(kAXSubroleAttribute) ?? ""
        return (role.localizedCaseInsensitiveContains("text")
            || subrole.localizedCaseInsensitiveContains("text")
            || subrole == "AXSearchField")
            && element.isAttributeSettable(kAXValueAttribute)
    }

    private func resetModifierOnlyCandidate() {
        modifierOnlyCandidateAction = nil
        modifierOnlyCandidateIsInvalid = false
    }

    private func localEnabledStatus(for shortcut: GlobalKeyboardShortcut) -> String {
        if AXIsProcessTrusted() {
            return "已启用（仅输入框）：\(shortcut.displayName)"
        }
        return "已启用，但需要辅助功能权限判断当前是否为输入框。"
    }

    private func savedShortcut(for action: Action) -> GlobalKeyboardShortcut? {
        switch action {
        case .nextInputMethod: appSettings.inputMethodShortcut
        case .toggleChineseEnglish: appSettings.chineseEnglishShortcut
        }
    }

    private func saveShortcut(_ shortcut: GlobalKeyboardShortcut, for action: Action) {
        switch action {
        case .nextInputMethod: appSettings.setInputMethodShortcut(shortcut)
        case .toggleChineseEnglish: appSettings.setChineseEnglishShortcut(shortcut)
        }
    }

    private func isEnabled(_ action: Action) -> Bool {
        switch action {
        case .nextInputMethod: appSettings.isInputMethodShortcutEnabled
        case .toggleChineseEnglish: appSettings.isChineseEnglishShortcutEnabled
        }
    }

    private func saveEnabled(_ enabled: Bool, for action: Action) {
        switch action {
        case .nextInputMethod: appSettings.setInputMethodShortcutEnabled(enabled)
        case .toggleChineseEnglish: appSettings.setChineseEnglishShortcutEnabled(enabled)
        }
    }

    private func perform(_ action: Action) {
        switch action {
        case .nextInputMethod:
            selectNextInputSource()
        case .toggleChineseEnglish:
            toggleChineseEnglishInputSource()
        }
    }

    private func selectableInputSources() -> [TISInputSource] {
        let rawSources = TISCreateInputSourceList(nil, false).takeRetainedValue()
            as NSArray
        return rawSources.compactMap { rawSource in
            let source = rawSource as! TISInputSource
            return isSelectable(source) ? source : nil
        }
    }

    private func selectNextInputSource() {
        let sources = selectableInputSources()
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let currentID = inputSourceIdentifier(current)
        guard sources.count > 1 else {
            updateStatus("没有找到其他可切换的输入法。", for: .nextInputMethod)
            return
        }
        let currentIndex = sources.firstIndex {
            inputSourceIdentifier($0) == currentID
        } ?? -1
        select(sources[(currentIndex + 1) % sources.count], for: .nextInputMethod)
    }

    private func toggleChineseEnglishInputSource() {
        let sources = selectableInputSources()
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let currentID = inputSourceIdentifier(current)
        let chineseSources = sources.filter(isChineseInputSource)
        // 部分中文输入法也会声明 ASCII 能力，因此必须把中文输入源排除，
        // 否则“切换中英文”可能仍然选中同一个中文输入法。
        let latinSources = sources.filter {
            isLatinInputSource($0) && !isChineseInputSource($0)
        }
        guard !chineseSources.isEmpty, !latinSources.isEmpty else {
            updateStatus(
                "需要至少一个中文输入法和一个英文键盘输入源。",
                for: .toggleChineseEnglish
            )
            return
        }

        if isChineseInputSource(current) {
            lastChineseInputSourceID = currentID
            let target = latinSources.first {
                inputSourceIdentifier($0) == lastLatinInputSourceID
            } ?? latinSources[0]
            select(target, for: .toggleChineseEnglish)
        } else {
            if isLatinInputSource(current) {
                lastLatinInputSourceID = currentID
            }
            let target = chineseSources.first {
                inputSourceIdentifier($0) == lastChineseInputSourceID
            } ?? chineseSources[0]
            select(target, for: .toggleChineseEnglish)
        }
    }

    private func select(_ source: TISInputSource, for action: Action) {
        let status = TISSelectInputSource(source)
        if status != noErr {
            updateStatus("切换输入法失败（错误 \(status)）。", for: action)
        }
    }

    private func isSelectable(_ source: TISInputSource) -> Bool {
        booleanProperty(source, key: kTISPropertyInputSourceIsSelectCapable)
            && stringProperty(source, key: kTISPropertyInputSourceCategory)
                == (kTISCategoryKeyboardInputSource as String)
    }

    private func isLatinInputSource(_ source: TISInputSource) -> Bool {
        booleanProperty(source, key: kTISPropertyInputSourceIsASCIICapable)
    }

    private func isChineseInputSource(_ source: TISInputSource) -> Bool {
        inputSourceLanguages(source).contains { language in
            language.lowercased().hasPrefix("zh")
        }
    }

    private func booleanProperty(_ source: TISInputSource, key: CFString) -> Bool {
        guard let rawValue = TISGetInputSourceProperty(source, key) else {
            return false
        }
        let value = Unmanaged<CFBoolean>
            .fromOpaque(rawValue)
            .takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private func inputSourceIdentifier(_ source: TISInputSource) -> String? {
        stringProperty(source, key: kTISPropertyInputSourceID)
    }

    private func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let rawValue = TISGetInputSourceProperty(
            source,
            key
        ) else {
            return nil
        }
        let value = Unmanaged<CFString>
            .fromOpaque(rawValue)
            .takeUnretainedValue()
        return value as String
    }

    private func inputSourceLanguages(_ source: TISInputSource) -> [String] {
        guard let rawValue = TISGetInputSourceProperty(
            source,
            kTISPropertyInputSourceLanguages
        ) else {
            return []
        }
        let value = Unmanaged<CFArray>
            .fromOpaque(rawValue)
            .takeUnretainedValue()
        return value as? [String] ?? []
    }

    private func updateStatus(_ text: String, for action: Action) {
        statusTexts[action] = text
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?()
        }
    }

    deinit {
        stop()
    }
}
