import AppKit

final class ActivationWindowController: NSObject, NSWindowDelegate {
    private let licenseManager: LicenseManager
    private let window: NSWindow
    private let machineCodeField = NSTextField(labelWithString: "-")
    private let activationCodeView = NSTextView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var activateButton = NSButton(
        title: "激活",
        target: self,
        action: #selector(activate)
    )
    private lazy var copyMachineCodeButton = NSButton(
        image: NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "复制加密设备码"
        ) ?? NSImage(),
        target: self,
        action: #selector(copyMachineCode)
    )

    var isVisible: Bool { window.isVisible }

    init(licenseManager: LicenseManager) {
        self.licenseManager = licenseManager
        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 520, height: 410)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        configureWindow()
    }

    func show() {
        dispatchPrecondition(condition: .onQueue(.main))
        refreshState()
        NSApp.setActivationPolicy(.accessory)
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(activationCodeView)
    }

    func closeAfterActivation() {
        window.orderOut(nil)
        activationCodeView.string = ""
    }

    func refreshState() {
        machineCodeField.stringValue = licenseManager.machineCode ?? "无法读取"
        copyMachineCodeButton.isEnabled = licenseManager.machineCode != nil
        statusLabel.stringValue = licenseManager.state.statusMessage
        switch licenseManager.state {
        case .missing:
            statusLabel.textColor = .secondaryLabelColor
        case .active:
            statusLabel.textColor = .systemGreen
        case .invalid, .expired, .clockRollback, .deviceUnavailable:
            statusLabel.textColor = .systemRed
        }
        activateButton.isEnabled = licenseManager.machineCode != nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    private func configureWindow() {
        window.title = "激活 MacWindowButtons"
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        window.contentView = makeContentView()
        window.center()
    }

    private func makeContentView() -> NSView {
        let contentView = NSVisualEffectView()
        contentView.material = .underWindowBackground
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.appearance = NSAppearance(named: .darkAqua)

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 58),
            iconView.heightAnchor.constraint(equalToConstant: 58)
        ])

        let titleLabel = NSTextField(labelWithString: "MacWindowButtons")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitleLabel = NSTextField(
            wrappingLabelWithString: "许可证与此 Mac 绑定。激活后才能启用窗口控制和快捷功能。"
        )
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 5

        let header = NSStackView(views: [iconView, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14

        let machineLabel = fieldLabel("加密设备码")
        machineCodeField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        machineCodeField.isSelectable = true
        machineCodeField.lineBreakMode = .byTruncatingMiddle
        machineCodeField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        copyMachineCodeButton.bezelStyle = .texturedRounded
        copyMachineCodeButton.imagePosition = .imageOnly
        copyMachineCodeButton.toolTip = "复制加密设备码"
        copyMachineCodeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            copyMachineCodeButton.widthAnchor.constraint(equalToConstant: 30),
            copyMachineCodeButton.heightAnchor.constraint(equalToConstant: 26)
        ])

        let machineRow = NSStackView(views: [
            machineCodeField,
            copyMachineCodeButton
        ])
        machineRow.orientation = .horizontal
        machineRow.alignment = .centerY
        machineRow.spacing = 8

        let activationLabel = fieldLabel("激活码")
        activationCodeView.isRichText = false
        activationCodeView.isAutomaticQuoteSubstitutionEnabled = false
        activationCodeView.isAutomaticDashSubstitutionEnabled = false
        activationCodeView.isAutomaticTextReplacementEnabled = false
        activationCodeView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        activationCodeView.textContainerInset = CGSize(width: 7, height: 7)
        activationCodeView.backgroundColor = .textBackgroundColor
        activationCodeView.textColor = .textColor

        let activationScrollView = NSScrollView()
        activationScrollView.documentView = activationCodeView
        activationScrollView.hasVerticalScroller = true
        activationScrollView.borderType = .bezelBorder
        activationScrollView.translatesAutoresizingMaskIntoConstraints = false
        activationScrollView.heightAnchor.constraint(equalToConstant: 92).isActive = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.maximumNumberOfLines = 2

        activateButton.bezelStyle = .rounded
        activateButton.keyEquivalent = "\r"
        let quitButton = NSButton(
            title: "退出",
            target: NSApp,
            action: #selector(NSApplication.terminate(_:))
        )
        quitButton.bezelStyle = .rounded

        let actions = NSStackView(views: [
            statusLabel,
            flexibleSpacer(),
            quitButton,
            activateButton
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [
            header,
            separator(),
            machineLabel,
            machineRow,
            activationLabel,
            activationScrollView,
            actions
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        machineRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        activationScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        actions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
        return contentView
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 472).isActive = true
        return box
    }

    @objc private func copyMachineCode() {
        guard let machineCode = licenseManager.machineCode else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(machineCode, forType: .string)
        statusLabel.stringValue = "加密设备码已复制。"
        statusLabel.textColor = .secondaryLabelColor
    }

    @objc private func activate() {
        let code = activationCodeView.string.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !code.isEmpty else {
            statusLabel.stringValue = "请输入激活码。"
            statusLabel.textColor = .systemRed
            NSSound.beep()
            return
        }

        activateButton.isEnabled = false
        defer { activateButton.isEnabled = licenseManager.machineCode != nil }
        do {
            let details = try licenseManager.activate(with: code)
            statusLabel.stringValue = "激活成功：\(details.validityDescription)"
            statusLabel.textColor = .systemGreen
        } catch {
            statusLabel.stringValue = error.localizedDescription
            statusLabel.textColor = .systemRed
            NSSound.beep()
        }
    }
}
