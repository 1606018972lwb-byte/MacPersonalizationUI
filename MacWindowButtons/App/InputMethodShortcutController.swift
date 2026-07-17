import AppKit
import Carbon

/// 注册输入源相关的自定义全局快捷键，并使用系统注册结果检测组合键冲突。
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

    private static let signature: OSType = 0x4D_57_42_49 // "MWBI"
    private let appSettings: AppSettings
    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [Action: EventHotKeyRef] = [:]
    private var statusTexts: [Action: String] = [:]
    private var lastLatinInputSourceID: String?
    private var lastChineseInputSourceID: String?
    var onStateChange: (() -> Void)?

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        Action.allCases.forEach { statusTexts[$0] = "默认关闭，请先录入快捷键。" }
    }

    func start() {
        installEventHandlerIfNeeded()
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
        Action.allCases.forEach(unregisterHotKey)
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func statusText(for action: Action) -> String {
        statusTexts[action] ?? ""
    }

    /// 录入后立即尝试全局注册。系统返回重复时不保存，原快捷键继续有效。
    func updateShortcut(
        _ shortcut: GlobalKeyboardShortcut,
        for action: Action
    ) -> RegistrationResult {
        dispatchPrecondition(condition: .onQueue(.main))
        if shortcut == savedShortcut(for: action) {
            return .success
        }

        var candidateReference: EventHotKeyRef?
        let status = register(
            shortcut,
            action: action,
            reference: &candidateReference
        )
        guard status == noErr else {
            return registrationFailure(status, shortcut: shortcut, action: action)
        }

        if isEnabled(action) {
            unregisterHotKey(action)
            registeredHotKeys[action] = candidateReference
        } else if let candidateReference {
            UnregisterEventHotKey(candidateReference)
        }
        saveShortcut(shortcut, for: action)
        updateStatus(
            isEnabled(action)
                ? "已启用：\(shortcut.displayName)"
                : "快捷键可用，勾选后启用：\(shortcut.displayName)",
            for: action
        )
        return .success
    }

    func setEnabled(_ enabled: Bool, for action: Action) -> RegistrationResult {
        dispatchPrecondition(condition: .onQueue(.main))
        guard enabled else {
            unregisterHotKey(action)
            saveEnabled(false, for: action)
            updateStatus("已关闭。", for: action)
            return .success
        }
        guard let shortcut = savedShortcut(for: action) else {
            updateStatus("请先点击输入框并按下一个组合键。", for: action)
            return .missingShortcut
        }
        if registeredHotKeys[action] != nil {
            saveEnabled(true, for: action)
            updateStatus("已启用：\(shortcut.displayName)", for: action)
            return .success
        }

        var reference: EventHotKeyRef?
        let status = register(shortcut, action: action, reference: &reference)
        guard status == noErr else {
            return registrationFailure(status, shortcut: shortcut, action: action)
        }
        registeredHotKeys[action] = reference
        saveEnabled(true, for: action)
        updateStatus("已启用：\(shortcut.displayName)", for: action)
        return .success
    }

    private func registrationFailure(
        _ status: OSStatus,
        shortcut: GlobalKeyboardShortcut,
        action: Action
    ) -> RegistrationResult {
        if status == eventHotKeyExistsErr {
            updateStatus(
                "快捷键 \(shortcut.displayName) 已被系统或其他应用占用。",
                for: action
            )
            return .conflict
        }
        let message = "无法注册快捷键（错误 \(status)）。"
        updateStatus(message, for: action)
        return .failed(message)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  hotKeyID.signature == InputMethodShortcutController.signature,
                  let action = Action(rawValue: hotKeyID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            let controller = Unmanaged<InputMethodShortcutController>
                .fromOpaque(userData)
                .takeUnretainedValue()
            controller.perform(action)
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func register(
        _ shortcut: GlobalKeyboardShortcut,
        action: Action,
        reference: inout EventHotKeyRef?
    ) -> OSStatus {
        installEventHandlerIfNeeded()
        return RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(from: shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: action.rawValue),
            GetApplicationEventTarget(),
            0,
            &reference
        )
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private func unregisterHotKey(_ action: Action) {
        if let reference = registeredHotKeys.removeValue(forKey: action) {
            UnregisterEventHotKey(reference)
        }
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
