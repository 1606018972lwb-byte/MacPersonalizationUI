import AppKit
import ApplicationServices
import CoreGraphics

/// 将 Finder 中单独按下的 Delete 转换为系统原生文件操作。
///
/// 可推出的已挂载卷使用 Command-E，普通文件和文件夹使用 Command-Delete。
/// Finder 原生负责完成操作、播放反馈和显示失败原因；其他应用的 Delete 不受影响。
final class DeleteToTrashShortcutController {
    private static let deleteKeyCodes: Set<Int64> = [51, 117]
    private static let syntheticEventMarker: Int64 = 0x4D574244
    private static let commandDeleteKeyCode: CGKeyCode = 51
    private static let commandEjectKeyCode: CGKeyCode = 14

    private let appSettings: AppSettings
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var settingsObserver: UUID?
    private var retryTimer: Timer?
    private var isWaitingForDeleteKeyUp = false

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        settingsObserver = appSettings.addDeleteShortcutObserver { [weak self] enabled in
            self?.applyEnabledState(enabled)
        }
    }

    deinit {
        stop()
        if let settingsObserver {
            appSettings.removeDeleteShortcutObserver(settingsObserver)
        }
    }

    func start() {
        applyEnabledState(appSettings.deleteMovesFilesToTrash)
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        isWaitingForDeleteKeyUp = false
    }

    private func applyEnabledState(_ enabled: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard enabled else {
            stop()
            return
        }
        installEventTapIfNeeded()
    }

    private func installEventTapIfNeeded() {
        guard eventTap == nil else {
            return
        }
        guard AXIsProcessTrusted() else {
            scheduleRetry()
            return
        }

        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let controller = Unmanaged<DeleteToTrashShortcutController>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            NSLog("[MacWindowButtons] 无法启用 Delete 快捷键，等待辅助功能权限")
            scheduleRetry()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        retryTimer?.invalidate()
        retryTimer = nil
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func scheduleRetry() {
        guard retryTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, appSettings.deleteMovesFilesToTrash else {
                self?.retryTimer?.invalidate()
                self?.retryTimer = nil
                return
            }
            installEventTapIfNeeded()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        // 本控制器生成的 Command-Delete 必须原样交给 Finder，不能再次作为
        // 用户按下的 Delete 处理，也不能提前清除物理按键的防重复状态。
        if event.getIntegerValueField(.eventSourceUserData)
            == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp,
           Self.deleteKeyCodes.contains(keyCode),
           isWaitingForDeleteKeyUp {
            isWaitingForDeleteKeyUp = false
            return nil
        }
        guard type == .keyDown,
              Self.deleteKeyCodes.contains(keyCode),
              event.flags.intersection([
                .maskCommand,
                .maskControl,
                .maskAlternate,
                .maskShift
              ]).isEmpty,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        else {
            return Unmanaged.passUnretained(event)
        }

        // 长按只执行一次，避免按键重复连续删除 Finder 后续自动选中的文件。
        if isWaitingForDeleteKeyUp
            || event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        let commandKeyCode = isEjectableVolumeSelected()
            ? Self.commandEjectKeyCode
            : Self.commandDeleteKeyCode
        guard postFinderCommand(keyCode: commandKeyCode) else {
            return Unmanaged.passUnretained(event)
        }
        isWaitingForDeleteKeyUp = true

        // 原始 Delete 必须被吞掉，只让 Finder 收到一次对应的系统原生命令。
        return nil
    }

    private func postFinderCommand(keyCode: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: false
              ) else {
            return false
        }

        for commandEvent in [keyDown, keyUp] {
            commandEvent.flags = .maskCommand
            commandEvent.setIntegerValueField(
                .eventSourceUserData,
                value: Self.syntheticEventMarker
            )
        }
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }

    private func isEjectableVolumeSelected() -> Bool {
        let selection = selectedFinderItems()
        let selectedPaths = Set(selection.urls.map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path
        })
        let selectedNames = Set(selection.names.map(normalizedFinderName))
        guard !selectedPaths.isEmpty || !selectedNames.isEmpty else {
            return false
        }

        let resourceKeys: Set<URLResourceKey> = [
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeNameKey
        ]
        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(resourceKeys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return mountedVolumes.contains { volumeURL in
            guard let values = try? volumeURL.resourceValues(forKeys: resourceKeys),
                  values.volumeIsEjectable == true || values.volumeIsRemovable == true else {
                return false
            }
            let path = volumeURL.standardizedFileURL.resolvingSymlinksInPath().path
            if selectedPaths.contains(path) {
                return true
            }

            // Finder 侧边栏的选中行通常没有 AXURL，只暴露卷的显示名称。
            let volumeNames = [values.volumeName, volumeURL.lastPathComponent]
                .compactMap { $0 }
                .map(normalizedFinderName)
            return volumeNames.contains { selectedNames.contains($0) }
        }
    }

    private func selectedFinderItems() -> (urls: [URL], names: [String]) {
        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else {
            return ([], [])
        }
        let applicationElement = AXUIElementCreateApplication(finder.processIdentifier)
        let focusedElement = axElement(
            from: applicationElement.copyAttribute(kAXFocusedUIElementAttribute)
        )

        var focusedSelectionElements: [AXUIElement] = []
        var focusedSelectionURLs: [URL] = []
        var element = focusedElement
        for _ in 0..<6 {
            guard let currentElement = element else {
                break
            }
            focusedSelectionElements.append(contentsOf: selectedElements(in: currentElement))
            if currentElement.boolAttribute(kAXSelectedAttribute) == true {
                focusedSelectionURLs.append(
                    contentsOf: urls(in: currentElement, remainingDepth: 4)
                )
            }
            element = axElement(from: currentElement.copyAttribute(kAXParentAttribute))
        }

        // 点击 Finder 侧边栏后，键盘焦点可能仍属于内容区。此时从整个当前
        // 窗口查找所有 AXSelectedRows/AXSelectedChildren，才能发现侧边栏选中行。
        guard let focusedWindow = axElement(
            from: applicationElement.copyAttribute(kAXFocusedWindowAttribute)
        ) else {
            let selection = finderItems(from: focusedSelectionElements)
            return (
                uniqueURLs(selection.urls + focusedSelectionURLs),
                selection.names
            )
        }
        let windowSelectionElements = selectedElementsInHierarchy(
            from: focusedWindow,
            maximumDepth: 9,
            maximumElements: 500
        )
        let selection = finderItems(
            from: focusedSelectionElements + windowSelectionElements
        )
        return (
            uniqueURLs(selection.urls + focusedSelectionURLs),
            selection.names
        )
    }

    private func selectedElementsInHierarchy(
        from root: AXUIElement,
        maximumDepth: Int,
        maximumElements: Int
    ) -> [AXUIElement] {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var result: [AXUIElement] = []
        var visited = 0
        var queueIndex = 0

        while queueIndex < queue.count, visited < maximumElements {
            let current = queue[queueIndex]
            queueIndex += 1
            visited += 1
            result.append(contentsOf: selectedElements(in: current.element))

            guard current.depth < maximumDepth,
                  let children = current.element.copyAttribute(kAXChildrenAttribute)
                    as? [AXUIElement] else {
                continue
            }
            queue.append(contentsOf: children.map { ($0, current.depth + 1) })
        }
        return result
    }

    private func finderItems(
        from selectedElements: [AXUIElement]
    ) -> (urls: [URL], names: [String]) {
        var urls: [URL] = []
        var names: [String] = []

        for selectedElement in selectedElements {
            let elementURLs = self.urls(in: selectedElement, remainingDepth: 4)
            if elementURLs.isEmpty {
                names.append(contentsOf: strings(in: selectedElement, remainingDepth: 4))
            } else {
                urls.append(contentsOf: elementURLs)
            }
        }
        return (uniqueURLs(urls), uniqueStrings(names))
    }

    private func selectedElements(in element: AXUIElement) -> [AXUIElement] {
        let attributes = [kAXSelectedRowsAttribute, kAXSelectedChildrenAttribute]
        var result: [AXUIElement] = []
        for attribute in attributes {
            if let selected = element.copyAttribute(attribute) as? [AXUIElement],
               !selected.isEmpty {
                result.append(contentsOf: selected)
            }
        }
        return result
    }

    private func urls(in element: AXUIElement, remainingDepth: Int) -> [URL] {
        var result: [URL] = []
        if let url = urlAttribute(of: element) {
            result.append(url)
        }
        guard remainingDepth > 0,
              let children = element.copyAttribute(kAXChildrenAttribute) as? [AXUIElement] else {
            return result
        }
        for child in children {
            result.append(contentsOf: urls(in: child, remainingDepth: remainingDepth - 1))
        }
        return result
    }

    private func urlAttribute(of element: AXUIElement) -> URL? {
        guard let value = element.copyAttribute(kAXURLAttribute) else {
            return nil
        }
        if let url = value as? URL {
            return url
        }
        if let text = value as? String {
            return URL(string: text)
        }
        return nil
    }

    private func strings(in element: AXUIElement, remainingDepth: Int) -> [String] {
        var result: [String] = []
        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value = element.copyAttribute(attribute) as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(value)
            }
        }
        guard remainingDepth > 0,
              let children = element.copyAttribute(kAXChildrenAttribute) as? [AXUIElement] else {
            return result
        }
        for child in children {
            result.append(contentsOf: strings(in: child, remainingDepth: remainingDepth - 1))
        }
        return result
    }

    private func axElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var paths: Set<String> = []
        return urls.filter { paths.insert($0.standardizedFileURL.path).inserted }
    }

    private func uniqueStrings(_ strings: [String]) -> [String] {
        var values: Set<String> = []
        return strings.filter { values.insert(normalizedFinderName($0)).inserted }
    }

    private func normalizedFinderName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}
