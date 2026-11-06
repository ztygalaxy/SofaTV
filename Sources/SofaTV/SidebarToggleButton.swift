import AppKit
import QuartzCore

/// A narrow edge tab; only its own bounds intercept mouse clicks.
final class SidebarToggleButton: NSButton {
    var onPointerActivity: (() -> Void)?
    var onTrackingChanged: ((Bool) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?
    private var collapsedState: Bool?

    init() {
        super.init(frame: .zero)
        title = ""; isBordered = false; imagePosition = .imageOnly
        setButtonType(.momentaryChange)
        focusRingType = .none; contentTintColor = .white
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = 9
        layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        layer?.masksToBounds = true
        setCollapsed(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setCollapsed(_ collapsed: Bool) {
        guard collapsedState != collapsed else { return }
        collapsedState = collapsed
        let label = collapsed ? "展开侧边栏" : "收起侧边栏"
        image = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        toolTip = label; setAccessibilityLabel(label)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self)
        addTrackingArea(area); pointerTrackingArea = area
    }
    override func resetCursorRects() { addCursorRect(visibleRect, cursor: .pointingHand) }
    override func mouseEntered(with event: NSEvent) { onPointerActivity?() }
    override func mouseMoved(with event: NSEvent) { onPointerActivity?() }
    override func mouseDown(with event: NSEvent) {
        onTrackingChanged?(true)
        super.mouseDown(with: event)
        onTrackingChanged?(false)
    }
}
