import AppKit

/// 点击后直接记录下一次带修饰键的物理按键组合。
private final class ShortcutRecorderButton: NSButton {
    var onShortcutRecorded: ((GlobalKeyboardShortcut) -> Void)?
    private let allowsModifierOnly: Bool
    private var savedShortcut: GlobalKeyboardShortcut?
    private var recordedModifiers: NSEvent.ModifierFlags = []
    private var isRecording = false

    init(allowsModifierOnly: Bool = false) {
        self.allowsModifierOnly = allowsModifierOnly
        super.init(frame: .zero)
        title = "点击录入"
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        focusRingType = .exterior
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    func show(_ shortcut: GlobalKeyboardShortcut?) {
        savedShortcut = shortcut
        title = shortcut?.displayName ?? "点击录入"
    }

    @objc private func beginRecording() {
        recordedModifiers = []
        isRecording = true
        window?.makeFirstResponder(self)
        title = allowsModifierOnly ? "请按下快捷键…" : "请按组合键…"
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelRecording()
            return
        }
        let modifiers = event.modifierFlags.intersection([
            .command,
            .option,
            .control,
            .shift
        ])
        guard !modifiers.isEmpty else {
            NSSound.beep()
            title = "需要修饰键"
            return
        }
        completeRecording(
            GlobalKeyboardShortcut(
                keyCode: UInt32(event.keyCode),
                modifierFlags: modifiers.rawValue
            )
        )
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording, allowsModifierOnly else {
            super.flagsChanged(with: event)
            return
        }
        let modifiers = event.modifierFlags.intersection([
            .command,
            .option,
            .control,
            .shift
        ])
        if !modifiers.isEmpty {
            recordedModifiers.formUnion(modifiers)
            title = GlobalKeyboardShortcut(
                keyCode: nil,
                modifierFlags: recordedModifiers.rawValue
            ).displayName
        } else if !recordedModifiers.isEmpty {
            completeRecording(
                GlobalKeyboardShortcut(
                    keyCode: nil,
                    modifierFlags: recordedModifiers.rawValue
                )
            )
        }
    }

    private func completeRecording(_ shortcut: GlobalKeyboardShortcut) {
        isRecording = false
        title = shortcut.displayName
        window?.makeFirstResponder(nil)
        onShortcutRecorded?(shortcut)
    }

    private func cancelRecording() {
        isRecording = false
        recordedModifiers = []
        show(savedShortcut)
        window?.makeFirstResponder(nil)
    }
}

/// 使用传统 macOS 偏好设置布局展示应用配置。
///
/// 顶部分段控件用于切换“常规、权限、更新、其他、快捷键、鼠标右键、关于”，所有页面共用同一个
/// 分组内容框，视觉结构接近经典桌面软件设置窗口。
final class ControlCenterViewController: NSViewController {
    private enum SettingsPage: Int, CaseIterable {
        case general
        case permission
        case update
        case other
        case shortcuts
        case contextMenu
        case about

        var title: String {
            switch self {
            case .general: "常规"
            case .permission: "权限"
            case .update: "更新"
            case .other: "其他"
            case .shortcuts: "快捷键"
            case .contextMenu: "鼠标右键"
            case .about: "关于"
            }
        }
    }

    private let applicationState: ApplicationState
    private let permissionManager: AccessibilityPermissionManager
    private let appSettings: AppSettings
    private let launchAtLoginController: LaunchAtLoginController
    private let updateManager: UpdateManager
    private let inputMethodShortcutController: InputMethodShortcutController
    private let finderContextMenuController: FinderContextMenuController
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
    private lazy var launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "登录时自动启动 MacWindowButtons",
        target: self,
        action: #selector(toggleLaunchAtLogin(_:))
    )
    private lazy var silentLaunchCheckbox = NSButton(
        checkboxWithTitle: "静默启动",
        target: self,
        action: #selector(toggleSilentLaunch(_:))
    )
    private let launchAtLoginStatusLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var openLoginItemsButton = NSButton(
        title: "打开登录项设置",
        target: self,
        action: #selector(openLoginItemsSettings)
    )
    private lazy var updateReminderCheckbox = NSButton(
        checkboxWithTitle: "自动检查并提醒我有新版本",
        target: self,
        action: #selector(toggleUpdateReminders(_:))
    )
    private lazy var automaticUpdateCheckbox = NSButton(
        checkboxWithTitle: "后台自动下载、验证并安装更新",
        target: self,
        action: #selector(toggleAutomaticUpdates(_:))
    )
    private lazy var updateIntervalPopup = NSPopUpButton(
        frame: .zero,
        pullsDown: false
    )
    private lazy var checkForUpdatesButton = NSButton(
        title: "立即检查",
        target: self,
        action: #selector(checkForUpdatesNow)
    )
    private lazy var openReleaseButton = NSButton(
        title: "查看新版本",
        target: self,
        action: #selector(openLatestRelease)
    )
    private let updateStatusLabel = NSTextField(wrappingLabelWithString: "尚未检查更新")
    private lazy var deleteToTrashCheckbox = NSButton(
        checkboxWithTitle: "按 Delete 删除文件或推出磁盘",
        target: self,
        action: #selector(toggleDeleteToTrashShortcut(_:))
    )
    private let deleteToTrashStatusLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var openKeyboardShortcutsButton = NSButton(
        title: "打开键盘快捷键设置…",
        target: self,
        action: #selector(openKeyboardShortcutSettings)
    )
    private lazy var inputMethodShortcutCheckbox = NSButton(
        checkboxWithTitle: "启用",
        target: self,
        action: #selector(toggleInputMethodShortcut(_:))
    )
    private lazy var chineseEnglishShortcutCheckbox = NSButton(
        checkboxWithTitle: "启用",
        target: self,
        action: #selector(toggleChineseEnglishShortcut(_:))
    )
    private let inputMethodShortcutRecorder = ShortcutRecorderButton(
        allowsModifierOnly: true
    )
    private let chineseEnglishShortcutRecorder = ShortcutRecorderButton(
        allowsModifierOnly: true
    )
    private let inputMethodShortcutStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let chineseEnglishShortcutStatusLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var finderContextMenuCheckbox = NSButton(
        checkboxWithTitle: "启用 Finder 鼠标右键菜单",
        target: self,
        action: #selector(toggleFinderContextMenu(_:))
    )
    private lazy var desktopShortcutMenuItemCheckbox = NSButton(
        checkboxWithTitle: "桌面快捷方式",
        target: self,
        action: #selector(toggleDesktopShortcutMenuItem(_:))
    )
    private lazy var desktopShortcutNameStylePopup = NSPopUpButton(
        frame: .zero,
        pullsDown: false
    )
    private let finderContextMenuStatusLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var controlAppearancePopup = NSPopUpButton(
        frame: .zero,
        pullsDown: false
    )
    private let pageContainer = NSView()
    private var pageViews: [NSView] = []

    init(
        applicationState: ApplicationState,
        permissionManager: AccessibilityPermissionManager,
        appSettings: AppSettings,
        launchAtLoginController: LaunchAtLoginController,
        updateManager: UpdateManager,
        inputMethodShortcutController: InputMethodShortcutController,
        finderContextMenuController: FinderContextMenuController,
        windowRefresher: WindowOverlayRefreshing
    ) {
        self.applicationState = applicationState
        self.permissionManager = permissionManager
        self.appSettings = appSettings
        self.launchAtLoginController = launchAtLoginController
        self.updateManager = updateManager
        self.inputMethodShortcutController = inputMethodShortcutController
        self.finderContextMenuController = finderContextMenuController
        self.windowRefresher = windowRefresher
        super.init(nibName: nil, bundle: nil)
        updateManager.onStateChange = { [weak self] in
            self?.refreshUpdateInterface()
        }
        inputMethodShortcutController.onStateChange = { [weak self] in
            self?.refreshShortcutInterface()
        }
        finderContextMenuController.onStateChange = { [weak self] in
            self?.refreshFinderContextMenuInterface()
        }
        preferredContentSize = CGSize(width: 640, height: 500)
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
            makePermissionPage(),
            makeUpdatePage(),
            makeOtherPage(),
            makeShortcutsPage(),
            makeContextMenuPage(),
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
            pageControl.widthAnchor.constraint(equalToConstant: 570),

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
        refreshLaunchAtLoginInterface()
        silentLaunchCheckbox.state = appSettings.launchesSilently ? .on : .off
        refreshUpdateInterface()
        refreshAppearanceInterface()
        refreshShortcutInterface()
        refreshFinderContextMenuInterface()
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
        launchAtLoginStatusLabel.font = .systemFont(ofSize: 11)
        launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        launchAtLoginStatusLabel.maximumNumberOfLines = 2
        openLoginItemsButton.bezelStyle = .rounded

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

        let loginRow = NSStackView(views: [
            launchAtLoginCheckbox,
            makeFlexibleSpacer(),
            openLoginItemsButton
        ])
        loginRow.orientation = .horizontal
        loginRow.alignment = .centerY

        let refreshRow = NSStackView(views: [
            makeFieldLabel("窗口扫描："),
            refreshButton,
            makeFlexibleSpacer()
        ])
        refreshRow.orientation = .horizontal
        refreshRow.alignment = .centerY
        refreshRow.spacing = 10

        let stack = NSStackView(views: [
            enableCheckbox,
            makeDetailLabel("控制行会显示在当前窗口顶部，左侧空白区域可以拖动窗口。"),
            makeSeparator(),
            sizeRow,
            makeDetailLabel("尺寸修改会立即应用到最小化、最大化和关闭按钮。"),
            makeSeparator(),
            silentLaunchCheckbox,
            makeDetailLabel("默认开启；启动时不自动打开设置窗口，只显示菜单栏图标。点击图标或再次启动应用仍可打开设置。"),
            makeSeparator(),
            loginRow,
            launchAtLoginStatusLabel,
            makeSeparator(),
            refreshRow,
            refreshStatusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        sizeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        loginRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        refreshRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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

    private func makeUpdatePage() -> NSView {
        updateReminderCheckbox.font = .systemFont(ofSize: 13)
        automaticUpdateCheckbox.font = .systemFont(ofSize: 13)

        updateIntervalPopup.addItems(
            withTitles: AppSettings.UpdateInterval.allCases.map(\.displayName)
        )
        updateIntervalPopup.target = self
        updateIntervalPopup.action = #selector(changeUpdateInterval(_:))
        updateIntervalPopup.translatesAutoresizingMaskIntoConstraints = false
        updateIntervalPopup.widthAnchor.constraint(equalToConstant: 125).isActive = true

        checkForUpdatesButton.bezelStyle = .rounded
        openReleaseButton.bezelStyle = .rounded
        updateStatusLabel.font = .systemFont(ofSize: 11)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.maximumNumberOfLines = 3

        let intervalRow = NSStackView(views: [
            makeFieldLabel("检查频率："),
            updateIntervalPopup,
            makeFlexibleSpacer()
        ])
        intervalRow.orientation = .horizontal
        intervalRow.alignment = .centerY
        intervalRow.spacing = 10

        let actionRow = NSStackView(views: [
            checkForUpdatesButton,
            openReleaseButton,
            makeFlexibleSpacer()
        ])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        let stack = NSStackView(views: [
            makeSectionTitle("更新提醒"),
            updateReminderCheckbox,
            intervalRow,
            makeDetailLabel("按设定周期同时查询 GitHub 与 Gitee；任一平台可用即可完成检查。"),
            makeSeparator(),
            makeSectionTitle("自动更新"),
            automaticUpdateCheckbox,
            makeDetailLabel(
                "仅在 DMG 提供 SHA-256 且应用标识、版本和代码签名均验证通过时静默安装；安装完成后应用会自动重启。"
            ),
            makeSeparator(),
            actionRow,
            updateStatusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        intervalRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        actionRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return pinStackToPage(stack)
    }

    private func makeOtherPage() -> NSView {
        controlAppearancePopup.addItems(
            withTitles: AppSettings.ControlAppearance.allCases.map(\.displayName)
        )
        controlAppearancePopup.target = self
        controlAppearancePopup.action = #selector(changeControlAppearance(_:))
        controlAppearancePopup.translatesAutoresizingMaskIntoConstraints = false
        controlAppearancePopup.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let appearanceRow = NSStackView(views: [
            makeFieldLabel("控制条风格："),
            controlAppearancePopup,
            makeFlexibleSpacer()
        ])
        appearanceRow.orientation = .horizontal
        appearanceRow.alignment = .centerY
        appearanceRow.spacing = 10

        let stack = NSStackView(views: [
            makeSectionTitle("窗口外观"),
            appearanceRow,
            makeDetailLabel(
                "两种样式都在窗口上方保留完整控制行；“与窗口一体”会将按钮以外区域设为透明。"
            ),
            makeSeparator(),
            makeSectionTitle("一体样式说明"),
            makeDetailLabel(
                "透明区域仍属于控制面板，按住空白处会由面板直接带动目标窗口移动；目标窗口位于预留行下方，不会遮挡其原有控件。"
            )
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        appearanceRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return pinStackToPage(stack)
    }

    private func makeShortcutsPage() -> NSView {
        openKeyboardShortcutsButton.bezelStyle = .rounded
        openKeyboardShortcutsButton.image = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: "键盘快捷键设置"
        )
        openKeyboardShortcutsButton.imagePosition = .imageLeading

        deleteToTrashCheckbox.font = .systemFont(ofSize: 13)
        deleteToTrashStatusLabel.font = .systemFont(ofSize: 11)
        deleteToTrashStatusLabel.textColor = .secondaryLabelColor
        deleteToTrashStatusLabel.maximumNumberOfLines = 2
        for label in [inputMethodShortcutStatusLabel, chineseEnglishShortcutStatusLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 2
        }
        for recorder in [inputMethodShortcutRecorder, chineseEnglishShortcutRecorder] {
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 170).isActive = true
        }
        inputMethodShortcutRecorder.onShortcutRecorded = { [weak self] shortcut in
            self?.recordShortcut(shortcut, for: .nextInputMethod)
        }
        chineseEnglishShortcutRecorder.onShortcutRecorded = { [weak self] shortcut in
            self?.recordShortcut(shortcut, for: .toggleChineseEnglish)
        }

        func shortcutRow(
            checkbox: NSButton,
            title: String,
            recorder: ShortcutRecorderButton
        ) -> NSStackView {
            let row = NSStackView(views: [
                checkbox,
                makeFieldLabel(title),
                makeFlexibleSpacer(),
                recorder
            ])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            return row
        }
        let inputMethodRow = shortcutRow(
            checkbox: inputMethodShortcutCheckbox,
            title: "切换输入法（仅输入框）",
            recorder: inputMethodShortcutRecorder
        )
        let chineseEnglishRow = shortcutRow(
            checkbox: chineseEnglishShortcutCheckbox,
            title: "切换中英文（仅输入框）",
            recorder: chineseEnglishShortcutRecorder
        )

        let stack = NSStackView(views: [
            makeSectionTitle("系统快捷键"),
            openKeyboardShortcutsButton,
            makeDetailLabel("打开 macOS“系统设置 → 键盘 → 键盘快捷键”。"),
            makeSeparator(),
            makeSectionTitle("输入法"),
            inputMethodRow,
            inputMethodShortcutStatusLabel,
            chineseEnglishRow,
            chineseEnglishShortcutStatusLabel,
            makeDetailLabel(
                "支持单修饰键、组合修饰键或修饰键＋普通键；两个功能不能使用相同组合，且只在文本输入区域生效。"
            ),
            makeSeparator(),
            makeSectionTitle("Finder 文件操作"),
            deleteToTrashCheckbox,
            makeDetailLabel(
                "启用后，选中已挂载的虚拟磁盘会安全推出；选中普通文件或文件夹则移到废纸篓。"
            ),
            deleteToTrashStatusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        inputMethodRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        chineseEnglishRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return pinStackToPage(stack)
    }

    private func makeContextMenuPage() -> NSView {
        finderContextMenuCheckbox.font = .systemFont(ofSize: 13)
        desktopShortcutMenuItemCheckbox.font = .systemFont(ofSize: 13)
        desktopShortcutNameStylePopup.addItems(
            withTitles: AppSettings.DesktopShortcutNameStyle.allCases.map(\.displayName)
        )
        desktopShortcutNameStylePopup.target = self
        desktopShortcutNameStylePopup.action = #selector(changeDesktopShortcutNameStyle(_:))
        desktopShortcutNameStylePopup.translatesAutoresizingMaskIntoConstraints = false
        desktopShortcutNameStylePopup.widthAnchor.constraint(equalToConstant: 170).isActive = true
        finderContextMenuStatusLabel.font = .systemFont(ofSize: 11)
        finderContextMenuStatusLabel.textColor = .secondaryLabelColor
        finderContextMenuStatusLabel.maximumNumberOfLines = 3

        let groupBox = NSBox()
        groupBox.boxType = .custom
        groupBox.titlePosition = .noTitle
        groupBox.cornerRadius = 5
        groupBox.borderWidth = 1
        groupBox.borderColor = .separatorColor
        groupBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.26)
        groupBox.translatesAutoresizingMaskIntoConstraints = false

        let groupRow = NSStackView(views: [
            desktopShortcutMenuItemCheckbox,
            makeFlexibleSpacer(),
            desktopShortcutNameStylePopup
        ])
        groupRow.orientation = .horizontal
        groupRow.alignment = .centerY
        groupRow.translatesAutoresizingMaskIntoConstraints = false

        let groupContent = NSView()
        groupContent.addSubview(groupRow)
        groupBox.contentView = groupContent
        NSLayoutConstraint.activate([
            groupRow.leadingAnchor.constraint(equalTo: groupContent.leadingAnchor, constant: 14),
            groupRow.trailingAnchor.constraint(equalTo: groupContent.trailingAnchor, constant: -14),
            groupRow.topAnchor.constraint(equalTo: groupContent.topAnchor, constant: 12),
            groupRow.bottomAnchor.constraint(equalTo: groupContent.bottomAnchor, constant: -12),
            groupBox.heightAnchor.constraint(equalToConstant: 48)
        ])

        let stack = NSStackView(views: [
            finderContextMenuCheckbox,
            makeDetailLabel("控制 MacWindowButtons 是否向 Finder 注册鼠标右键菜单。"),
            finderContextMenuStatusLabel,
            makeSeparator(),
            makeSectionTitle("发送到"),
            groupBox,
            makeDetailLabel("在 Finder 中选中文件或文件夹后，可创建不复制原文件的桌面替身。")
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        groupBox.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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

    private func refreshLaunchAtLoginInterface() {
        let state = launchAtLoginController.state
        launchAtLoginCheckbox.state = state.isEnabled ? .on : .off
        switch state {
        case .enabled:
            launchAtLoginStatusLabel.stringValue = "已启用，登录 macOS 后应用会在后台启动。"
            launchAtLoginStatusLabel.textColor = .secondaryLabelColor
            openLoginItemsButton.isHidden = true
        case .disabled:
            launchAtLoginStatusLabel.stringValue = "当前未启用开机自启动。"
            launchAtLoginStatusLabel.textColor = .secondaryLabelColor
            openLoginItemsButton.isHidden = true
        case .requiresApproval:
            launchAtLoginStatusLabel.stringValue = "需要在系统设置的“登录项”中允许此应用。"
            launchAtLoginStatusLabel.textColor = .systemOrange
            openLoginItemsButton.isHidden = false
        case .unavailable:
            launchAtLoginStatusLabel.stringValue = "当前安装方式不支持登录项，请把应用移到“应用程序”后重试。"
            launchAtLoginStatusLabel.textColor = .systemOrange
            openLoginItemsButton.isHidden = false
        }
    }

    private func refreshUpdateInterface() {
        guard isViewLoaded else {
            return
        }
        updateReminderCheckbox.state = appSettings.checksForUpdates ? .on : .off
        automaticUpdateCheckbox.state = appSettings.automaticallyInstallsUpdates ? .on : .off
        automaticUpdateCheckbox.isEnabled = appSettings.checksForUpdates
        updateIntervalPopup.isEnabled = appSettings.checksForUpdates
        if let index = AppSettings.UpdateInterval.allCases.firstIndex(
            of: appSettings.updateInterval
        ) {
            updateIntervalPopup.selectItem(at: index)
        }
        checkForUpdatesButton.isEnabled = !updateManager.isChecking
        openReleaseButton.isHidden = updateManager.latestRelease == nil
        updateStatusLabel.stringValue = updateManager.statusText
    }

    private func refreshAppearanceInterface() {
        if let index = AppSettings.ControlAppearance.allCases.firstIndex(
            of: appSettings.controlAppearance
        ) {
            controlAppearancePopup.selectItem(at: index)
        }
    }

    private func refreshShortcutInterface() {
        guard isViewLoaded else {
            return
        }

        inputMethodShortcutCheckbox.state = appSettings.isInputMethodShortcutEnabled
            ? .on
            : .off
        chineseEnglishShortcutCheckbox.state = appSettings.isChineseEnglishShortcutEnabled
            ? .on
            : .off
        inputMethodShortcutRecorder.show(appSettings.inputMethodShortcut)
        chineseEnglishShortcutRecorder.show(appSettings.chineseEnglishShortcut)
        updateShortcutStatus(
            inputMethodShortcutStatusLabel,
            action: .nextInputMethod,
            enabled: appSettings.isInputMethodShortcutEnabled
        )
        updateShortcutStatus(
            chineseEnglishShortcutStatusLabel,
            action: .toggleChineseEnglish,
            enabled: appSettings.isChineseEnglishShortcutEnabled
        )

        deleteToTrashCheckbox.state = appSettings.deleteMovesFilesToTrash ? .on : .off
        if !appSettings.deleteMovesFilesToTrash {
            deleteToTrashStatusLabel.stringValue = "默认关闭，勾选后立即启用。"
            deleteToTrashStatusLabel.textColor = .secondaryLabelColor
        } else if permissionManager.isTrusted {
            deleteToTrashStatusLabel.stringValue = "已启用：Delete 会推出虚拟磁盘，或将普通文件移到废纸篓。"
            deleteToTrashStatusLabel.textColor = .systemGreen
        } else {
            deleteToTrashStatusLabel.stringValue = "已启用，但需要辅助功能权限才能监听全局按键。"
            deleteToTrashStatusLabel.textColor = .systemOrange
        }
    }

    private func refreshFinderContextMenuInterface() {
        guard isViewLoaded else {
            return
        }

        finderContextMenuCheckbox.state = appSettings.isFinderContextMenuEnabled
            ? .on
            : .off
        desktopShortcutMenuItemCheckbox.state = appSettings.isDesktopShortcutMenuItemEnabled
            ? .on
            : .off
        if let styleIndex = AppSettings.DesktopShortcutNameStyle.allCases.firstIndex(
            of: appSettings.desktopShortcutNameStyle
        ) {
            desktopShortcutNameStylePopup.selectItem(at: styleIndex)
        }
        finderContextMenuCheckbox.isEnabled = !finderContextMenuController.isApplying
        desktopShortcutMenuItemCheckbox.isEnabled = appSettings.isFinderContextMenuEnabled
            && !finderContextMenuController.isApplying
        desktopShortcutNameStylePopup.isEnabled = appSettings.isFinderContextMenuEnabled
            && appSettings.isDesktopShortcutMenuItemEnabled
            && !finderContextMenuController.isApplying
        finderContextMenuStatusLabel.stringValue = finderContextMenuController.statusText
        if finderContextMenuController.hasError {
            finderContextMenuStatusLabel.textColor = .systemOrange
        } else if case .enabled = finderContextMenuController.registrationState {
            finderContextMenuStatusLabel.textColor = .systemGreen
        } else {
            finderContextMenuStatusLabel.textColor = .secondaryLabelColor
        }
    }

    private func updateShortcutStatus(
        _ label: NSTextField,
        action: InputMethodShortcutController.Action,
        enabled: Bool
    ) {
        let status = inputMethodShortcutController.statusText(for: action)
        label.stringValue = status
        if status.contains("冲突") || status.contains("占用")
            || status.contains("错误") || status.contains("需要") {
            label.textColor = .systemOrange
        } else if enabled {
            label.textColor = .systemGreen
        } else {
            label.textColor = .secondaryLabelColor
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

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            try launchAtLoginController.setEnabled(sender.state == .on)
            refreshLaunchAtLoginInterface()
            if launchAtLoginController.state == .requiresApproval {
                showLoginItemApprovalAlert()
            }
        } catch {
            sender.state = .off
            refreshLaunchAtLoginInterface()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法启用开机自启动"
            alert.informativeText = "\(error.localizedDescription)\n\n请在系统设置的“通用 → 登录项”中允许 MacWindowButtons。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                launchAtLoginController.openSystemSettings()
            }
        }
    }

    @objc private func toggleSilentLaunch(_ sender: NSButton) {
        appSettings.setLaunchesSilently(sender.state == .on)
    }

    @objc private func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    private func showLoginItemApprovalAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要允许后台登录项"
        alert.informativeText = "macOS 已记录开机启动请求，请在系统设置中允许 MacWindowButtons。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            launchAtLoginController.openSystemSettings()
        }
    }

    @objc private func toggleUpdateReminders(_ sender: NSButton) {
        appSettings.setChecksForUpdates(sender.state == .on)
        refreshUpdateInterface()
        if sender.state == .on {
            updateManager.checkIfDue()
        }
    }

    @objc private func toggleAutomaticUpdates(_ sender: NSButton) {
        appSettings.setAutomaticallyInstallsUpdates(sender.state == .on)
        refreshUpdateInterface()
    }

    @objc private func changeUpdateInterval(_ sender: NSPopUpButton) {
        let intervals = AppSettings.UpdateInterval.allCases
        guard intervals.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        appSettings.setUpdateInterval(intervals[sender.indexOfSelectedItem])
    }

    @objc private func checkForUpdatesNow() {
        updateManager.checkNow()
    }

    @objc private func openLatestRelease() {
        updateManager.openLatestReleasePage()
    }

    @objc private func changeControlAppearance(_ sender: NSPopUpButton) {
        let appearances = AppSettings.ControlAppearance.allCases
        guard appearances.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        appSettings.setControlAppearance(appearances[sender.indexOfSelectedItem])
    }

    @objc private func toggleDeleteToTrashShortcut(_ sender: NSButton) {
        let enabled = sender.state == .on
        appSettings.setDeleteMovesFilesToTrash(enabled)
        refreshShortcutInterface()
        if enabled && !permissionManager.isTrusted {
            permissionManager.requestPermissionFromUser()
        }
    }

    @objc private func toggleFinderContextMenu(_ sender: NSButton) {
        finderContextMenuController.setContextMenuEnabled(sender.state == .on)
        refreshFinderContextMenuInterface()
    }

    @objc private func toggleDesktopShortcutMenuItem(_ sender: NSButton) {
        finderContextMenuController.setDesktopShortcutEnabled(sender.state == .on)
        refreshFinderContextMenuInterface()
    }

    @objc private func changeDesktopShortcutNameStyle(_ sender: NSPopUpButton) {
        let styles = AppSettings.DesktopShortcutNameStyle.allCases
        guard styles.indices.contains(sender.indexOfSelectedItem) else {
            return
        }
        appSettings.setDesktopShortcutNameStyle(
            styles[sender.indexOfSelectedItem]
        )
    }

    @objc private func openKeyboardShortcutSettings() {
        let workspace = NSWorkspace.shared
        let urls = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?KeyboardShortcuts",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"
        ]
        for text in urls {
            if let url = URL(string: text), workspace.open(url) {
                return
            }
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法打开键盘快捷键设置"
        alert.informativeText = "请手动打开“系统设置 → 键盘 → 键盘快捷键”。"
        alert.runModal()
    }

    @objc private func toggleInputMethodShortcut(_ sender: NSButton) {
        setShortcutEnabled(
            sender.state == .on,
            action: .nextInputMethod,
            checkbox: sender
        )
    }

    @objc private func toggleChineseEnglishShortcut(_ sender: NSButton) {
        setShortcutEnabled(
            sender.state == .on,
            action: .toggleChineseEnglish,
            checkbox: sender
        )
    }

    private func setShortcutEnabled(
        _ enabled: Bool,
        action: InputMethodShortcutController.Action,
        checkbox: NSButton
    ) {
        let result = inputMethodShortcutController.setEnabled(enabled, for: action)
        guard case .success = result else {
            checkbox.state = .off
            showShortcutRegistrationAlert(result)
            refreshShortcutInterface()
            return
        }
        if enabled && !permissionManager.isTrusted {
            permissionManager.requestPermissionFromUser()
        }
        refreshShortcutInterface()
    }

    private func recordShortcut(
        _ shortcut: GlobalKeyboardShortcut,
        for action: InputMethodShortcutController.Action
    ) {
        let result = inputMethodShortcutController.updateShortcut(shortcut, for: action)
        if case .success = result {
            refreshShortcutInterface()
            return
        }
        showShortcutRegistrationAlert(result)
        refreshShortcutInterface()
    }

    private func showShortcutRegistrationAlert(
        _ result: InputMethodShortcutController.RegistrationResult
    ) {
        let detail: String
        switch result {
        case .success:
            return
        case .missingShortcut:
            detail = "请先点击右侧录入框，然后按下单修饰键、组合修饰键或“修饰键＋普通键”。"
        case .conflict:
            detail = "这个组合键与本页另一个输入法功能重复，请换一个组合键。"
        case let .failed(message):
            detail = message
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法使用此快捷键"
        alert.informativeText = detail
        alert.runModal()
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
