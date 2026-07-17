import AppKit
import ApplicationServices
import CoreGraphics

/// 将 Finder 中单独按下的 Delete 转换为系统原生的 Command-Delete。
///
/// Finder 原生负责移动文件、播放反馈以及提供“撤销移到废纸篓”，本工具只负责
/// 补齐 Windows 用户熟悉的单键入口。事件只在 Finder 位于前台时处理，其他应用
/// 收到的 Delete 不会被修改。
final class DeleteToTrashShortcutController {
    private static let deleteKeyCodes: Set<Int64> = [51, 117]
    private static let syntheticEventMarker: Int64 = 0x4D574244

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

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)
        else {
            return Unmanaged.passUnretained(event)
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.setIntegerValueField(
            .eventSourceUserData,
            value: Self.syntheticEventMarker
        )
        keyUp.setIntegerValueField(
            .eventSourceUserData,
            value: Self.syntheticEventMarker
        )
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        isWaitingForDeleteKeyUp = true

        // 原始 Delete 必须被吞掉，只让 Finder 收到一次系统原生 Command-Delete。
        return nil
    }
}
