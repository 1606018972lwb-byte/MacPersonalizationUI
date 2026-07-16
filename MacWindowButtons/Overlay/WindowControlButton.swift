import AppKit

/// 右侧控制条中的单个按钮，负责图标、悬停反馈和辅助功能标签。
final class WindowControlButton: NSButton {
    enum Kind {
        case minimize
        case maximize
        case close

        var symbolName: String {
            switch self {
            case .minimize: "minus"
            case .maximize: "rectangle"
            case .close: "xmark"
            }
        }

        var accessibilityTitle: String {
            switch self {
            case .minimize: "最小化窗口"
            case .maximize: "最大化窗口"
            case .close: "关闭窗口"
            }
        }
    }

    let kind: Kind
    private var trackingAreaReference: NSTrackingArea?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)

        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        focusRingType = .none
        toolTip = kind.accessibilityTitle
        setAccessibilityLabel(kind.accessibilityTitle)
        wantsLayer = true
        layer?.cornerRadius = 5
        updateSymbol(named: kind.symbolName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// 最大化状态改变时将单方框切换成重叠方框。
    func showRestoreSymbol(_ shouldShowRestore: Bool) {
        guard kind == .maximize else {
            return
        }
        updateSymbol(named: shouldShowRestore ? "rectangle.on.rectangle" : "rectangle")
        toolTip = shouldShowRestore ? "还原窗口" : "最大化窗口"
        if let toolTip {
            setAccessibilityLabel(toolTip)
        }
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = hoverColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    private var hoverColor: NSColor {
        if kind == .close {
            return NSColor.systemRed.withAlphaComponent(0.82)
        }
        return NSColor.labelColor.withAlphaComponent(0.14)
    }

    private func updateSymbol(named symbolName: String) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: kind.accessibilityTitle
        )?.withSymbolConfiguration(configuration)
        contentTintColor = .labelColor
    }
}
