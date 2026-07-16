import AppKit

/// 菜单栏图标点击后展示的应用控制中心。
///
/// 该界面集中提供权限状态、功能开关、按钮大小和退出操作，避免用户必须
/// 猜测菜单项含义。缺少权限时会使用醒目的状态卡片和可点击按钮提示。
final class ControlCenterViewController: NSViewController {
    private let applicationState: ApplicationState
    private let permissionManager: AccessibilityPermissionManager
    private let appSettings: AppSettings
    private weak var windowRefresher: WindowOverlayRefreshing?

    private let permissionBox = NSBox()
    private let permissionIcon = NSImageView()
    private let permissionTitleLabel = NSTextField(labelWithString: "")
    private let permissionDetailLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var permissionButton = NSButton(
        title: "",
        target: self,
        action: #selector(showPermissionHelp)
    )
    private lazy var enableSwitch: NSSwitch = {
        let control = NSSwitch()
        control.target = self
        control.action = #selector(toggleWindowButtons(_:))
        return control
    }()
    private lazy var sizeControl = NSSegmentedControl(
        labels: AppSettings.ControlSize.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: self,
        action: #selector(changeControlSize(_:))
    )
    private lazy var autoHideSwitch: NSSwitch = {
        let control = NSSwitch()
        control.target = self
        control.action = #selector(toggleAutoHide(_:))
        return control
    }()
    private lazy var refreshButton = NSButton(
        title: "刷新所有程序窗口",
        target: self,
        action: #selector(refreshAllWindows)
    )
    private let refreshStatusLabel = NSTextField(wrappingLabelWithString: "扫描运行中的应用，并在目标窗口右上角显示三个控件。")

    init(
        applicationState: ApplicationState,
        permissionManager: AccessibilityPermissionManager,
        appSettings: AppSettings,
        windowRefresher: WindowOverlayRefreshing
    ) {
        self.applicationState = applicationState
        self.permissionManager = permissionManager
        self.appSettings = appSettings
        self.windowRefresher = windowRefresher
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 340, height: 470)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .popover
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        view = backgroundView

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(contentStack)

        contentStack.addArrangedSubview(makeHeaderView())
        contentStack.addArrangedSubview(makePermissionView())
        contentStack.addArrangedSubview(makeEnableRow())
        contentStack.addArrangedSubview(makeSizeSection())
        contentStack.addArrangedSubview(makeAutoHideRow())
        contentStack.addArrangedSubview(makeRefreshSection())
        contentStack.addArrangedSubview(makeFooterView())

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -18),
            contentStack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -14)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshInterface()
    }

    /// 在弹出界面已显示时刷新权限、开关和大小选择状态。
    func refreshInterface() {
        guard isViewLoaded else {
            return
        }

        let isTrusted = permissionManager.isTrusted
        updatePermissionCard(isTrusted: isTrusted)
        enableSwitch.state = applicationState.areWindowButtonsEnabled && isTrusted ? .on : .off
        autoHideSwitch.state = appSettings.automaticallyHidesControls ? .on : .off

        if let selectedIndex = AppSettings.ControlSize.allCases.firstIndex(
            of: appSettings.controlSize
        ) {
            sizeControl.selectedSegment = selectedIndex
        }
    }

    /// 权限刚生效或主界面重新打开时，自动启用功能并立即扫描窗口。
    func refreshWindowsAfterPermissionGrant() {
        guard permissionManager.isTrusted,
              let windowRefresher else {
            return
        }
        applicationState.enableWindowButtons()
        enableSwitch.state = .on
        updateRefreshStatus(with: windowRefresher.refreshAllWindows())
    }

    private func makeHeaderView() -> NSView {
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48)
        ])

        let titleLabel = NSTextField(labelWithString: "MacWindowButtons")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        let subtitleLabel = NSTextField(labelWithString: "让窗口控制按钮出现在右侧")
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        let header = NSStackView(views: [iconView, labels])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        return header
    }

    private func makePermissionView() -> NSView {
        permissionBox.boxType = .custom
        permissionBox.cornerRadius = 9
        permissionBox.borderWidth = 1
        permissionBox.translatesAutoresizingMaskIntoConstraints = false

        permissionIcon.imageScaling = .scaleProportionallyDown
        permissionIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            permissionIcon.widthAnchor.constraint(equalToConstant: 20),
            permissionIcon.heightAnchor.constraint(equalToConstant: 20)
        ])

        permissionTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        permissionDetailLabel.font = .systemFont(ofSize: 10)
        permissionDetailLabel.textColor = .secondaryLabelColor
        permissionDetailLabel.maximumNumberOfLines = 2

        let labels = NSStackView(views: [permissionTitleLabel, permissionDetailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .small

        let row = NSStackView(views: [permissionIcon, labels, makeFlexibleSpacer(), permissionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(row)
        permissionBox.contentView = container
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 11),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -11),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            permissionBox.widthAnchor.constraint(equalToConstant: 304),
            permissionBox.heightAnchor.constraint(equalToConstant: 62)
        ])
        return permissionBox
    }

    private func makeEnableRow() -> NSView {
        let title = NSTextField(labelWithString: "显示右侧窗口按钮")
        title.font = .systemFont(ofSize: 13, weight: .medium)

        let row = NSStackView(views: [title, makeFlexibleSpacer(), enableSwitch])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 304).isActive = true
        return row
    }

    private func makeSizeSection() -> NSView {
        let title = NSTextField(labelWithString: "按钮大小")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        sizeControl.segmentStyle = .rounded
        sizeControl.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, sizeControl])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        NSLayoutConstraint.activate([
            sizeControl.widthAnchor.constraint(equalToConstant: 304)
        ])
        return stack
    }

    private func makeAutoHideRow() -> NSView {
        let title = NSTextField(labelWithString: "自动隐藏，避免遮挡")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let detail = NSTextField(labelWithString: "移到窗口右侧蓝色提示条时展开")
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        let row = NSStackView(views: [labels, makeFlexibleSpacer(), autoHideSwitch])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 304).isActive = true
        return row
    }

    private func makeRefreshSection() -> NSView {
        refreshButton.bezelStyle = .rounded
        refreshButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "刷新所有程序窗口"
        )
        refreshButton.imagePosition = .imageLeading
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        refreshStatusLabel.font = .systemFont(ofSize: 10)
        refreshStatusLabel.textColor = .secondaryLabelColor
        refreshStatusLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [refreshButton, refreshStatusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 304),
            refreshButton.widthAnchor.constraint(equalToConstant: 304)
        ])
        return stack
    }

    private func makeFooterView() -> NSView {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "-"
        let versionLabel = NSTextField(labelWithString: "版本 \(version)")
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor

        let quitButton = NSButton(
            title: "退出应用",
            target: self,
            action: #selector(quitApplication)
        )
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small

        let row = NSStackView(views: [versionLabel, makeFlexibleSpacer(), quitButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 304).isActive = true
        return row
    }

    private func updatePermissionCard(isTrusted: Bool) {
        if isTrusted {
            permissionTitleLabel.stringValue = "辅助功能权限已开启"
            permissionDetailLabel.stringValue = "窗口跟随与三个控制按钮可以工作"
            permissionButton.title = "查看"
            permissionIcon.image = NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: "已授权"
            )
            permissionIcon.contentTintColor = .systemGreen
            permissionBox.fillColor = NSColor.systemGreen.withAlphaComponent(0.09)
            permissionBox.borderColor = NSColor.systemGreen.withAlphaComponent(0.25)
        } else {
            permissionTitleLabel.stringValue = "缺少辅助功能权限"
            permissionDetailLabel.stringValue = "开关已打开仍无效时，请点击重新授权"
            permissionButton.title = "重新授权"
            permissionIcon.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "缺少权限"
            )
            permissionIcon.contentTintColor = .systemOrange
            permissionBox.fillColor = NSColor.systemOrange.withAlphaComponent(0.11)
            permissionBox.borderColor = NSColor.systemOrange.withAlphaComponent(0.32)
        }
    }

    private func makeFlexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    @objc private func showPermissionHelp() {
        if permissionManager.isTrusted {
            permissionManager.showPermissionStatus()
            return
        }

        permissionButton.isEnabled = false
        permissionDetailLabel.stringValue = "正在清理旧权限记录…"
        permissionManager.repairPermissionFromUser { [weak self] errorMessage in
            guard let self else {
                return
            }
            permissionButton.isEnabled = true
            if let errorMessage {
                permissionDetailLabel.stringValue = errorMessage
            } else {
                permissionDetailLabel.stringValue = "请在系统提示中打开设置并重新开启权限"
            }
        }
    }

    @objc private func toggleWindowButtons(_ sender: NSSwitch) {
        if sender.state == .on && !permissionManager.isTrusted {
            sender.state = .off
            permissionManager.requestPermissionFromUser()
            refreshInterface()
            return
        }

        if sender.state == .on {
            applicationState.enableWindowButtons()
        } else {
            applicationState.pauseWindowButtons()
        }
    }

    @objc private func changeControlSize(_ sender: NSSegmentedControl) {
        let sizes = AppSettings.ControlSize.allCases
        guard sizes.indices.contains(sender.selectedSegment) else {
            NSLog("[MacWindowButtons] 无法识别界面中的按钮大小选项")
            return
        }
        appSettings.setControlSize(sizes[sender.selectedSegment])
    }

    @objc private func toggleAutoHide(_ sender: NSSwitch) {
        appSettings.setAutomaticallyHidesControls(sender.state == .on)
        refreshStatusLabel.stringValue = sender.state == .on
            ? "控件已移到标题栏下方；移入右侧蓝色提示条即可展开。"
            : "控件将常驻标题栏下方，可能覆盖少量窗口内容。"
    }

    @objc private func refreshAllWindows() {
        guard permissionManager.isTrusted else {
            refreshStatusLabel.stringValue = "缺少辅助功能权限，授权后才能扫描窗口。"
            refreshInterface()
            return
        }

        guard let windowRefresher else {
            refreshStatusLabel.stringValue = "窗口刷新服务当前不可用。"
            NSLog("[MacWindowButtons] 窗口刷新服务已失效")
            return
        }

        updateRefreshStatus(with: windowRefresher.refreshAllWindows())
    }

    private func updateRefreshStatus(with result: WindowRefreshResult) {
        enableSwitch.state = .on
        if result.discoveredWindowCount == 0 {
            refreshStatusLabel.stringValue = "没有找到可控制的普通应用窗口。"
        } else if let targetApplicationName = result.targetApplicationName,
                  result.areControlsVisible {
            if appSettings.automaticallyHidesControls {
                refreshStatusLabel.stringValue = "已扫描 \(result.discoveredWindowCount) 个窗口，控件已在 \(targetApplicationName) 右侧短暂展开，之后移入蓝色提示条即可显示。"
            } else {
                refreshStatusLabel.stringValue = "已扫描 \(result.discoveredWindowCount) 个窗口，三个控件已显示在 \(targetApplicationName) 右侧。"
            }
        } else {
            refreshStatusLabel.stringValue = "已扫描 \(result.discoveredWindowCount) 个窗口，请点击一个目标窗口。"
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
