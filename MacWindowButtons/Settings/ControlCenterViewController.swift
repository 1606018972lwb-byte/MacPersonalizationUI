import AppKit

/// 使用传统 macOS 偏好设置布局展示应用配置。
///
/// 顶部分段控件用于切换“常规、按钮、权限、关于”，所有页面共用同一个
/// 分组内容框，视觉结构接近经典桌面软件设置窗口。
final class ControlCenterViewController: NSViewController {
    private enum SettingsPage: Int, CaseIterable {
        case general
        case buttons
        case permission
        case about

        var title: String {
            switch self {
            case .general: "常规"
            case .buttons: "按钮"
            case .permission: "权限"
            case .about: "关于"
            }
        }
    }

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
    private lazy var enableCheckbox = NSButton(
        checkboxWithTitle: "显示窗口顶部控制行",
        target: self,
        action: #selector(toggleWindowButtons(_:))
    )
    private lazy var sizeControl = NSSegmentedControl(
        labels: AppSettings.ControlSize.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: self,
        action: #selector(changeControlSize(_:))
    )
    private lazy var pageControl = NSSegmentedControl(
        labels: SettingsPage.allCases.map(\.title),
        trackingMode: .selectOne,
        target: self,
        action: #selector(selectSettingsPage(_:))
    )
    private lazy var refreshButton = NSButton(
        title: "刷新所有程序窗口",
        target: self,
        action: #selector(refreshAllWindows)
    )
    private let refreshStatusLabel = NSTextField(
        wrappingLabelWithString: "扫描运行中的应用，并为当前目标窗口显示顶部控制行。"
    )
    private let pageContainer = NSView()
    private var pageViews: [NSView] = []

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
        preferredContentSize = CGSize(width: 640, height: 410)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .underWindowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.appearance = NSAppearance(named: .darkAqua)
        view = backgroundView

        pageControl.segmentStyle = .rounded
        pageControl.selectedSegment = SettingsPage.general.rawValue
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(pageControl)

        let contentBox = NSBox()
        contentBox.boxType = .custom
        contentBox.titlePosition = .noTitle
        contentBox.borderWidth = 1
        contentBox.cornerRadius = 5
        contentBox.borderColor = .separatorColor
        contentBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.34)
        contentBox.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(contentBox)

        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        let boxContent = NSView()
        boxContent.addSubview(pageContainer)
        contentBox.contentView = boxContent

        pageViews = [
            makeGeneralPage(),
            makeButtonsPage(),
            makePermissionPage(),
            makeAboutPage()
        ]
        pageViews.enumerated().forEach { index, page in
            page.translatesAutoresizingMaskIntoConstraints = false
            page.isHidden = index != SettingsPage.general.rawValue
            pageContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
                page.topAnchor.constraint(equalTo: pageContainer.topAnchor),
                page.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            pageControl.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 12),
            pageControl.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            pageControl.widthAnchor.constraint(equalToConstant: 360),

            contentBox.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 16),
            contentBox.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -16),
            contentBox.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: -1),
            contentBox.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -16),

            pageContainer.leadingAnchor.constraint(equalTo: boxContent.leadingAnchor, constant: 22),
            pageContainer.trailingAnchor.constraint(equalTo: boxContent.trailingAnchor, constant: -22),
            pageContainer.topAnchor.constraint(equalTo: boxContent.topAnchor, constant: 24),
            pageContainer.bottomAnchor.constraint(equalTo: boxContent.bottomAnchor, constant: -20)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshInterface()
    }

    /// 在设置窗口显示时同步权限、功能开关和按钮大小。
    func refreshInterface() {
        guard isViewLoaded else {
            return
        }

        let isTrusted = permissionManager.isTrusted
        updatePermissionCard(isTrusted: isTrusted)
        enableCheckbox.state = applicationState.areWindowButtonsEnabled && isTrusted
            ? .on
            : .off
        if let selectedIndex = AppSettings.ControlSize.allCases.firstIndex(
            of: appSettings.controlSize
        ) {
            sizeControl.selectedSegment = selectedIndex
        }
    }

    /// 权限刚生效时自动启用功能并立即扫描窗口。
    func refreshWindowsAfterPermissionGrant() {
        guard permissionManager.isTrusted,
              let windowRefresher else {
            return
        }
        applicationState.enableWindowButtons()
        enableCheckbox.state = .on
        updateRefreshStatus(with: windowRefresher.refreshAllWindows())
    }

    private func makeGeneralPage() -> NSView {
        enableCheckbox.font = .systemFont(ofSize: 13)

        refreshButton.bezelStyle = .rounded
        refreshButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "刷新所有程序窗口"
        )
        refreshButton.imagePosition = .imageLeading

        refreshStatusLabel.font = .systemFont(ofSize: 11)
        refreshStatusLabel.textColor = .secondaryLabelColor
        refreshStatusLabel.maximumNumberOfLines = 3

        let behaviorStack = NSStackView(views: [
            makeSectionTitle("窗口行为"),
            enableCheckbox,
            makeDetailLabel("控制行会显示在当前窗口顶部，左侧空白区域可以拖动窗口。")
        ])
        behaviorStack.orientation = .vertical
        behaviorStack.alignment = .leading
        behaviorStack.spacing = 10

        let refreshRow = NSStackView(views: [
            makeFieldLabel("窗口扫描："),
            refreshButton,
            makeFlexibleSpacer()
        ])
        refreshRow.orientation = .horizontal
        refreshRow.alignment = .centerY
        refreshRow.spacing = 10

        let scanStack = NSStackView(views: [
            makeSectionTitle("运行状态"),
            refreshRow,
            refreshStatusLabel
        ])
        scanStack.orientation = .vertical
        scanStack.alignment = .leading
        scanStack.spacing = 10

        return makePageStack([behaviorStack, makeSeparator(), scanStack])
    }

    private func makeButtonsPage() -> NSView {
        sizeControl.segmentStyle = .rounded
        sizeControl.translatesAutoresizingMaskIntoConstraints = false
        sizeControl.widthAnchor.constraint(equalToConstant: 250).isActive = true

        let sizeRow = NSStackView(views: [
            makeFieldLabel("按钮大小："),
            sizeControl,
            makeFlexibleSpacer()
        ])
        sizeRow.orientation = .horizontal
        sizeRow.alignment = .centerY
        sizeRow.spacing = 10

        let preview = NSBox()
        preview.boxType = .custom
        preview.titlePosition = .noTitle
        preview.borderWidth = 1
        preview.cornerRadius = 5
        preview.borderColor = .separatorColor
        preview.fillColor = NSColor.black.withAlphaComponent(0.18)

        let previewTitle = NSTextField(labelWithString: "空白拖动区域")
        previewTitle.textColor = .secondaryLabelColor
        previewTitle.font = .systemFont(ofSize: 12)
        let symbols = NSTextField(labelWithString: "—     □     ×")
        symbols.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        symbols.alignment = .center
        let previewRow = NSStackView(views: [
            previewTitle,
            makeFlexibleSpacer(),
            symbols
        ])
        previewRow.orientation = .horizontal
        previewRow.alignment = .centerY
        previewRow.spacing = 12
        previewRow.translatesAutoresizingMaskIntoConstraints = false
        let previewContent = NSView()
        previewContent.addSubview(previewRow)
        preview.contentView = previewContent
        NSLayoutConstraint.activate([
            previewRow.leadingAnchor.constraint(equalTo: previewContent.leadingAnchor, constant: 14),
            previewRow.trailingAnchor.constraint(equalTo: previewContent.trailingAnchor, constant: -14),
            previewRow.centerYAnchor.constraint(equalTo: previewContent.centerYAnchor),
            preview.heightAnchor.constraint(equalToConstant: 54)
        ])

        let stack = NSStackView(views: [
            makeSectionTitle("窗口控制按钮"),
            sizeRow,
            makeDetailLabel("尺寸修改会立即应用到最小化、最大化和关闭按钮。"),
            makeSeparator(),
            makeSectionTitle("布局预览"),
            preview,
            makeDetailLabel("控制行宽度始终与目标窗口一致，三个按钮固定在最右侧。")
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return pinStackToPage(stack)
    }

    private func makePermissionPage() -> NSView {
        let permissionView = makePermissionView()
        let explanation = makeDetailLabel(
            "MacWindowButtons 只使用 macOS 辅助功能接口读取和控制窗口，"
                + "不会注入其他应用，也不会修改系统文件。"
        )
        explanation.maximumNumberOfLines = 3

        let stack = NSStackView(views: [
            makeSectionTitle("辅助功能权限"),
            permissionView,
            explanation,
            makeSeparator(),
            makeSectionTitle("权限没有立即生效？"),
            makeDetailLabel("请关闭再重新打开系统设置中的权限开关，然后返回此窗口。")
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        permissionView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return pinStackToPage(stack)
    }

    private func makeAboutPage() -> NSView {
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72)
        ])

        let title = NSTextField(labelWithString: "MacWindowButtons")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "-"
        let versionLabel = NSTextField(labelWithString: "版本 \(version)")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        let description = makeDetailLabel("让 macOS 窗口拥有靠右显示的 Windows 风格控制按钮。")

        let labels = NSStackView(views: [title, versionLabel, description])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 6

        let header = NSStackView(views: [iconView, labels])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16

        let quitButton = NSButton(
            title: "退出应用",
            target: self,
            action: #selector(quitApplication)
        )
        quitButton.bezelStyle = .rounded

        let footer = NSStackView(views: [
            makeDetailLabel("Swift + AppKit · macOS 13 或更高版本"),
            makeFlexibleSpacer(),
            quitButton
        ])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let stack = NSStackView(views: [header, makeSeparator(), footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return pinStackToPage(stack)
    }

    private func makePermissionView() -> NSView {
        permissionBox.boxType = .custom
        permissionBox.titlePosition = .noTitle
        permissionBox.cornerRadius = 5
        permissionBox.borderWidth = 1
        permissionBox.translatesAutoresizingMaskIntoConstraints = false

        permissionIcon.imageScaling = .scaleProportionallyDown
        permissionIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            permissionIcon.widthAnchor.constraint(equalToConstant: 24),
            permissionIcon.heightAnchor.constraint(equalToConstant: 24)
        ])

        permissionTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        permissionDetailLabel.font = .systemFont(ofSize: 11)
        permissionDetailLabel.textColor = .secondaryLabelColor
        permissionDetailLabel.maximumNumberOfLines = 2

        let labels = NSStackView(views: [permissionTitleLabel, permissionDetailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        permissionButton.bezelStyle = .rounded
        let row = NSStackView(views: [
            permissionIcon,
            labels,
            makeFlexibleSpacer(),
            permissionButton
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 11
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(row)
        permissionBox.contentView = container
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 13),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -13),
            permissionBox.heightAnchor.constraint(equalToConstant: 74)
        ])
        return permissionBox
    }

    private func makePageStack(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        return pinStackToPage(stack)
    }

    private func pinStackToPage(_ stack: NSStackView) -> NSView {
        let page = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            stack.topAnchor.constraint(equalTo: page.topAnchor)
        ])
        return page
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }

    private func makeDetailLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func makeFlexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func updatePermissionCard(isTrusted: Bool) {
        if isTrusted {
            permissionTitleLabel.stringValue = "辅助功能权限已开启"
            permissionDetailLabel.stringValue = "实时窗口跟随与三个控制按钮可以正常工作"
            permissionButton.title = "查看系统设置"
            permissionIcon.image = NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: "已授权"
            )
            permissionIcon.contentTintColor = .systemGreen
            permissionBox.fillColor = NSColor.systemGreen.withAlphaComponent(0.08)
            permissionBox.borderColor = NSColor.systemGreen.withAlphaComponent(0.30)
        } else {
            permissionTitleLabel.stringValue = "缺少辅助功能权限"
            permissionDetailLabel.stringValue = "授权后才能读取、移动和控制其他应用窗口"
            permissionButton.title = "重新授权"
            permissionIcon.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "缺少权限"
            )
            permissionIcon.contentTintColor = .systemOrange
            permissionBox.fillColor = NSColor.systemOrange.withAlphaComponent(0.09)
            permissionBox.borderColor = NSColor.systemOrange.withAlphaComponent(0.34)
        }
    }

    @objc private func selectSettingsPage(_ sender: NSSegmentedControl) {
        guard SettingsPage(rawValue: sender.selectedSegment) != nil else {
            return
        }
        pageViews.enumerated().forEach { index, page in
            page.isHidden = index != sender.selectedSegment
        }
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
            permissionDetailLabel.stringValue = errorMessage
                ?? "请在系统提示中打开设置并重新开启权限"
        }
    }

    @objc private func toggleWindowButtons(_ sender: NSButton) {
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
        enableCheckbox.state = .on
        if result.discoveredWindowCount == 0 {
            refreshStatusLabel.stringValue = "没有找到可控制的普通应用窗口。"
        } else if let targetApplicationName = result.targetApplicationName,
                  result.areControlsVisible {
            refreshStatusLabel.stringValue = "已扫描 \(result.discoveredWindowCount) 个窗口，已为 \(targetApplicationName) 显示控制行。"
        } else {
            refreshStatusLabel.stringValue = "已扫描 \(result.discoveredWindowCount) 个窗口，请点击一个目标窗口。"
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
