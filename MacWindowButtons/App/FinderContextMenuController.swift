import Foundation

/// 管理 Finder Sync 扩展的注册状态，使设置页开关真实控制右键菜单。
final class FinderContextMenuController {
    enum RegistrationState {
        case checking
        case changing(enabled: Bool)
        case enabled
        case disabled
        case failed(String)
    }

    private enum ExtensionState {
        case enabled
        case disabled
        case missing
    }

    private static let extensionIdentifier = "com.lwb.MacWindowButtons.FinderExtension"
    private static let extensionRelativePath =
        "Contents/PlugIns/MacWindowButtonsFinder.appex"

    private let appSettings: AppSettings
    private let workQueue = DispatchQueue(
        label: "com.lwb.MacWindowButtons.finder-context-menu",
        qos: .userInitiated
    )
    private var isOperational = false
    private var needsReapply = false

    private(set) var registrationState: RegistrationState = .checking
    private(set) var isApplying = false
    var onStateChange: (() -> Void)?

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    var statusText: String {
        switch registrationState {
        case .checking:
            "正在检查 Finder 右键菜单状态…"
        case let .changing(enabled):
            enabled ? "正在注册 Finder 右键菜单…" : "正在关闭 Finder 右键菜单…"
        case .enabled:
            "已启用：Finder 右键菜单会显示“发送到 → 桌面快捷方式”。"
        case .disabled where appSettings.isFinderContextMenuEnabled:
            "“发送到”组当前没有启用的命令，Finder 右键菜单已关闭。"
        case .disabled:
            "已关闭：Finder 右键菜单不会显示 MacWindowButtons 命令。"
        case let .failed(message):
            "切换失败：\(message)"
        }
    }

    var hasError: Bool {
        if case .failed = registrationState {
            return true
        }
        return false
    }

    func start() {
        isOperational = true
        applyCurrentConfiguration()
    }

    func stop() {
        isOperational = false
        applyCurrentConfiguration()
    }

    func setContextMenuEnabled(_ enabled: Bool) {
        appSettings.setFinderContextMenuEnabled(enabled)
        applyCurrentConfiguration()
    }

    func setDesktopShortcutEnabled(_ enabled: Bool) {
        appSettings.setDesktopShortcutMenuItemEnabled(enabled)
        applyCurrentConfiguration()
    }

    func applyCurrentConfiguration() {
        guard !isApplying else {
            needsReapply = true
            return
        }

        let shouldEnable = isOperational
            && appSettings.isFinderContextMenuEnabled
            && appSettings.isDesktopShortcutMenuItemEnabled
        isApplying = true
        registrationState = .changing(enabled: shouldEnable)
        onStateChange?()

        workQueue.async { [weak self] in
            guard let self else {
                return
            }

            let result = Result {
                try self.setExtensionEnabled(shouldEnable)
                return try self.currentExtensionState()
            }

            DispatchQueue.main.async {
                self.isApplying = false
                switch result {
                case let .success(state):
                    switch state {
                    case .enabled:
                        self.registrationState = .enabled
                    case .disabled, .missing:
                        self.registrationState = .disabled
                    }
                case let .failure(error):
                    self.registrationState = .failed(error.localizedDescription)
                }
                self.onStateChange?()
                if self.needsReapply {
                    self.needsReapply = false
                    self.applyCurrentConfiguration()
                }
            }
        }
    }

    private func setExtensionEnabled(_ enabled: Bool) throws {
        if enabled {
            let extensionURL = Bundle.main.bundleURL.appendingPathComponent(
                Self.extensionRelativePath
            )
            guard FileManager.default.fileExists(atPath: extensionURL.path) else {
                throw ControllerError("安装中缺少 Finder 扩展")
            }
            _ = try runPlugInKit(arguments: ["-a", extensionURL.path])
        }

        _ = try runPlugInKit(arguments: [
            "-e",
            enabled ? "use" : "ignore",
            "-i",
            Self.extensionIdentifier
        ])
    }

    private func currentExtensionState() throws -> ExtensionState {
        let output = try runPlugInKit(arguments: [
            "-m",
            "-A",
            "-D",
            "-v",
            "-i",
            Self.extensionIdentifier
        ])
        guard let line = output.split(separator: "\n").first(
            where: { $0.contains(Self.extensionIdentifier) }
        ) else {
            return .missing
        }
        return line.trimmingCharacters(in: .whitespaces).hasPrefix("+")
            ? .enabled
            : .disabled
    }

    private func runPlugInKit(arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ControllerError(detail?.isEmpty == false ? detail! : "系统未接受扩展状态变更")
        }
        return output
    }
}

private struct ControllerError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
