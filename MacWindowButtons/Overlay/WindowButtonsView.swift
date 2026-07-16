import AppKit

/// 承载最小化、最大化/还原和关闭按钮的半透明原生视觉效果视图。
final class WindowButtonsView: NSVisualEffectView {
    let minimizeButton = WindowControlButton(kind: .minimize)
    let maximizeButton = WindowControlButton(kind: .maximize)
    let closeButton = WindowControlButton(kind: .close)

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
        stackView.spacing = 1
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            minimizeButton.widthAnchor.constraint(equalToConstant: 36),
            maximizeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.widthAnchor.constraint(equalToConstant: 36)
        ])
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
}
