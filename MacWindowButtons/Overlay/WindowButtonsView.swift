import AppKit

/// 绘制与目标窗口同宽的半透明占位行，三个窗口按钮固定排列在最右侧。
final class WindowButtonsView: NSVisualEffectView {
    let minimizeButton = WindowControlButton(kind: .minimize)
    let maximizeButton = WindowControlButton(kind: .maximize)
    let closeButton = WindowControlButton(kind: .close)
    private var buttonWidthConstraints: [NSLayoutConstraint] = []
    private var buttonHeightConstraints: [NSLayoutConstraint] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true

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
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ] + buttonWidthConstraints + buttonHeightConstraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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
        buttonWidthConstraints.forEach { constraint in
            constraint.constant = controlSize.buttonWidth
        }
        buttonHeightConstraints.forEach { constraint in
            constraint.constant = controlSize.buttonHeight
        }
        minimizeButton.updateSymbolPointSize(controlSize.symbolPointSize)
        maximizeButton.updateSymbolPointSize(controlSize.symbolPointSize)
        closeButton.updateSymbolPointSize(controlSize.symbolPointSize)
        layer?.cornerRadius = controlSize == .large ? 8 : 7
    }
}
