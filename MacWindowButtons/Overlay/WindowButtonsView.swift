import AppKit

/// 悬浮样式绘制整行背景；一体样式只保留三个按钮，其余区域由原窗口直接接收事件。
final class WindowButtonsView: NSView {
    let minimizeButton = WindowControlButton(kind: .minimize)
    let maximizeButton = WindowControlButton(kind: .maximize)
    let closeButton = WindowControlButton(kind: .close)
    var onEmptyAreaDragBegan: ((CGPoint) -> Void)?
    var onEmptyAreaDragged: ((CGPoint) -> Void)?
    var onEmptyAreaDragEnded: (() -> Void)?
    private var buttonWidthConstraints: [NSLayoutConstraint] = []
    private var buttonHeightConstraints: [NSLayoutConstraint] = []
    private var controlSize: AppSettings.ControlSize = .standard
    private let backgroundView = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true

        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 7
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        let stackView = NSStackView(views: [minimizeButton, maximizeButton, closeButton])
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        buttonWidthConstraints = [
            minimizeButton.widthAnchor.constraint(equalToConstant: 36),
            maximizeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.widthAnchor.constraint(equalToConstant: 36)
        ]
        buttonHeightConstraints = [
            minimizeButton.heightAnchor.constraint(equalToConstant: 35),
            maximizeButton.heightAnchor.constraint(equalToConstant: 35),
            closeButton.heightAnchor.constraint(equalToConstant: 35)
        ]
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
        ] + buttonWidthConstraints + buttonHeightConstraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// 空白占位区域充当目标窗口的标题栏；按钮区域仍由各按钮自行接收点击。
    override func mouseDown(with event: NSEvent) {
        onEmptyAreaDragBegan?(NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        onEmptyAreaDragged?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        onEmptyAreaDragEnded?()
    }

    /// 按目标窗口能力禁用不支持的操作，并更新最大化按钮图标。
    func updateCapabilities(for window: TargetWindow, showsRestore: Bool) {
        minimizeButton.isEnabled = window.canMinimize
        maximizeButton.isEnabled = window.canResize
        closeButton.isEnabled = window.canClose
        maximizeButton.showRestoreSymbol(showsRestore)
    }

    /// 同步三个按钮真实宽高和图标点大小，整个矩形都是鼠标命中区域。
    func applyControlSize(_ controlSize: AppSettings.ControlSize) {
        self.controlSize = controlSize
        buttonWidthConstraints.forEach { constraint in
            constraint.constant = controlSize.buttonWidth
        }
        buttonHeightConstraints.forEach { constraint in
            constraint.constant = controlSize.buttonHeight
        }
        minimizeButton.updateSymbolPointSize(controlSize.symbolPointSize)
        maximizeButton.updateSymbolPointSize(controlSize.symbolPointSize)
        closeButton.updateSymbolPointSize(controlSize.symbolPointSize)
        backgroundView.layer?.cornerRadius = controlSize == .large ? 8 : 7
    }

    /// 切换当前悬浮外观和贴合目标窗口的标题栏外观。
    func applyAppearance(_ appearance: AppSettings.ControlAppearance) {
        switch appearance {
        case .floating:
            backgroundView.isHidden = false
            backgroundView.material = .hudWindow
            backgroundView.layer?.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
        case .integrated:
            // 一体模式完全不绘制背景。面板本身也会缩到只有三个按钮宽，透明区域
            // 不属于任何悬浮窗口，因此点击、文字输入和原生标题栏拖动可直接穿透。
            backgroundView.isHidden = true
        }
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.cornerRadius = controlSize == .large ? 8 : 7
    }
}
