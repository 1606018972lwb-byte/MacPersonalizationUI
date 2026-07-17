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
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var eventTapRetryTimer: Timer?
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
        updateEventTapState()
    }

    func stop() {
        stopEventTap()
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
            updateEventTapState()
            return .success
        }
        guard let shortcut = savedShortcut(for: action) else {
            updateStatus("请先点击输入框并按下一个组合键。", for: action)
            return .missingShortcut
        }
        saveEnabled(true, for: action)
        updateStatus(localEnabledStatus(for: shortcut), for: action)
        updateEventTapState()
        return .success
    }

    /// CGEventTap 比 NSEvent 全局观察器更可靠地接收 VS Code、Electron 和浏览器
    /// 中的修饰键变化。回调始终返回原事件，只观察而不拦截应用自己的快捷键。
    private func installEventTapIfNeeded() {
        guard eventTap == nil else {
            return
        }
        guard AXIsProcessTrusted() else {
            scheduleEventTapRetry()
            return
        }

        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let controller = Unmanaged<InputMethodShortcutController>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return controller.handleEventTap(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[MacWindowButtons] 无法创建输入法快捷键事件监听，等待辅助功能权限")
            scheduleEventTapRetry()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        eventTapRunLoopSource = source
        eventTapRetryTimer?.invalidate()
        eventTapRetryTimer = nil
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[MacWindowButtons] 输入法快捷键事件监听已启用")
    }

    private func handleEventTap(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        handleLocalShortcutEvent(
            type: type,
            keyCode: UInt32(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: relevantModifiers(event.flags),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        return Unmanaged.passUnretained(event)
    }

    private func updateEventTapState() {
        if Action.allCases.contains(where: isEnabled) {
            installEventTapIfNeeded()
        } else {
            stopEventTap()
        }
    }

    private func scheduleEventTapRetry() {
        guard eventTapRetryTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self,
                  Action.allCases.contains(where: isEnabled) else {
                self?.eventTapRetryTimer?.invalidate()
                self?.eventTapRetryTimer = nil
                return
            }
            installEventTapIfNeeded()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        eventTapRetryTimer = timer
    }

    private func stopEventTap() {
        eventTapRetryTimer?.invalidate()
        eventTapRetryTimer = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        eventTapRunLoopSource = nil
        eventTap = nil
        resetModifierOnlyCandidate()
    }

    private func handleLocalShortcutEvent(
        type: CGEventType,
        keyCode: UInt32,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) {
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

        if type == .keyDown {
            // 任意普通键都会取消正在等待释放的纯修饰键组合，避免
            // Command-Shift-T 等三键快捷键被误判成 Command-Shift。
            modifierOnlyCandidateIsInvalid = true
            guard !isRepeat else {
                return
            }
            guard let match = enabledShortcuts.first(where: {
                $0.shortcut.keyCode == keyCode
                    && $0.shortcut.modifiers == modifiers
            }),
                  isFocusedElementTextInput() else {
                return
            }
            perform(match.action)
            return
        }

        guard type == .flagsChanged else {
            return
        }
        let modifierOnlyShortcuts = enabledShortcuts.filter {
            $0.shortcut.keyCode == nil
        }
        handleModifierOnlyShortcut(
            currentModifiers: modifiers,
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
        _ flags: CGEventFlags
    ) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }

    /// 通过当前前台进程的 AXFocusedUIElement 判断光标是否位于可编辑文本区域。
    /// Electron/Chromium 编辑器不总是报告标准 AXTextArea，因此同时检查文本选择、
    /// 插入点、可写 Value 和语义描述等能力，而不是只依赖三个固定角色名。
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
        let element = deepestFocusedElement(from: rawElement as! AXUIElement)
        let role = element.stringAttribute(kAXRoleAttribute) ?? ""
        let subrole = element.stringAttribute(kAXSubroleAttribute) ?? ""
        let textRoles: Set<String> = [
            "AXTextField",
            "AXTextArea",
            "AXTextView",
            "AXComboBox",
            "AXSearchField"
        ]
        if textRoles.contains(role) || subrole == "AXSearchField" {
            return true
        }

        let attributes = attributeNames(of: element)
        let hasSelectionRange = attributes.contains(kAXSelectedTextRangeAttribute)
        let hasTextEditingState = hasSelectionRange
            && (attributes.contains(kAXSelectedTextAttribute)
                || attributes.contains(kAXVisibleCharacterRangeAttribute)
                || attributes.contains("AXInsertionPointLineNumber")
                || attributes.contains("AXNumberOfCharacters"))
        if hasTextEditingState {
            return true
        }

        let excludedValueRoles: Set<String> = [
            "AXButton",
            "AXCheckBox",
            "AXRadioButton",
            "AXSlider",
            "AXMenuItem",
            "AXPopUpButton",
            "AXTabGroup"
        ]
        if element.isAttributeSettable(kAXValueAttribute),
           !excludedValueRoles.contains(role) {
            return true
        }

        let semanticText = [
            role,
            subrole,
            element.stringAttribute(kAXDescriptionAttribute) ?? "",
            element.stringAttribute(kAXHelpAttribute) ?? ""
        ].joined(separator: " ").lowercased()
        let editorKeywords = [
            "text",
            "editor",
            "input",
            "textarea",
            "编辑",
            "输入"
        ]
        if editorKeywords.contains(where: semanticText.contains),
           (attributes.contains(kAXValueAttribute) || hasSelectionRange) {
            return true
        }

        NSLog(
            "[MacWindowButtons] 已识别输入法快捷键，但当前焦点不是可编辑文本：%@/%@ (%@)",
            role,
            subrole,
            application.bundleIdentifier ?? "unknown"
        )
        return false
    }

    /// 某些 Electron 应用先把焦点报告在编辑器容器，再通过容器自己的
    /// AXFocusedUIElement 指向实际文本节点；向下解析可覆盖 VS Code/网页编辑器。
    private func deepestFocusedElement(from root: AXUIElement) -> AXUIElement {
        var current = root
        for _ in 0..<4 {
            guard let rawChild = current.copyAttribute(kAXFocusedUIElementAttribute),
                  CFGetTypeID(rawChild) == AXUIElementGetTypeID() else {
                break
            }
            let child = rawChild as! AXUIElement
            guard CFHash(child) != CFHash(current) else {
                break
            }
            current = child
        }
        return current
    }

    private func attributeNames(of element: AXUIElement) -> Set<String> {
        var rawNames: CFArray?
        guard AXUIElementCopyAttributeNames(element, &rawNames) == .success,
              let names = rawNames as? [String] else {
            return []
        }
        return Set(names)
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
