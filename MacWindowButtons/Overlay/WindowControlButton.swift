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
    private var currentSymbolName: String
    private var symbolPointSize: CGFloat = 12

    /// NSButton 默认会为标题栏风格预留上下 alignment inset，导致 Auto Layout
    /// 约束为 35pt 时实际 frame 只有约 31pt。清零后，完整矩形都是命中区域。
    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    init(kind: Kind) {
        self.kind = kind
        currentSymbolName = kind.symbolName
        super.init(frame: .zero)

        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        focusRingType = .none
        toolTip = kind.accessibilityTitle
        setAccessibilityLabel(kind.accessibilityTitle)
        wantsLayer = true
        // 外层控制条负责裁剪圆角；按钮本身保持完整矩形，让悬停颜色明确覆盖
        // 从上到下、从左到右的全部可点击区域。
        layer?.cornerRadius = 0
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
        currentSymbolName = shouldShowRestore ? "rectangle.on.rectangle" : "rectangle"
        updateSymbol(named: currentSymbolName)
        toolTip = shouldShowRestore ? "还原窗口" : "最大化窗口"
        if let toolTip {
            setAccessibilityLabel(toolTip)
        }
    }

    /// 按用户选择调整 SF Symbol 点大小。
    func updateSymbolPointSize(_ pointSize: CGFloat) {
        symbolPointSize = pointSize
        updateSymbol(named: currentSymbolName)
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
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
        image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: kind.accessibilityTitle
        )?.withSymbolConfiguration(configuration)
        contentTintColor = .labelColor
    }
}
