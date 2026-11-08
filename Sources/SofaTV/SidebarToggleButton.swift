import AppKit
import QuartzCore

/// A narrow edge tab; only its own bounds intercept mouse clicks.
final class SidebarToggleButton: NSButton {
    var onPointerActivity: (() -> Void)?
    var onTrackingChanged: ((Bool) -> Void)?
    var leadingResizeInset: CGFloat = 0 {
        didSet { if oldValue != leadingResizeInset { window?.invalidateCursorRects(for: self) } }
    }
    private var pointerTrackingArea: NSTrackingArea?
    private var collapsedState: Bool?
    private var tracking = false

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
    override func resetCursorRects() {
        let rect = visibleRect.intersection(NSRect(x: bounds.minX + leadingResizeInset, y: bounds.minY,
                                                   width: max(0, bounds.width - leadingResizeInset), height: bounds.height))
        if !rect.isEmpty { addCursorRect(rect, cursor: isEnabled ? .pointingHand : .arrow) }
    }
    override func mouseEntered(with event: NSEvent) { onPointerActivity?() }
    override func mouseMoved(with event: NSEvent) { onPointerActivity?() }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !tracking else { return }
        onPointerActivity?()
        tracking = true
        onTrackingChanged?(true)
    }
    override func mouseDragged(with event: NSEvent) { if tracking { onPointerActivity?() } }
    override func mouseUp(with event: NSEvent) {
        guard tracking else { return }
        let activate = isEnabled && !isHidden && bounds.contains(convert(event.locationInWindow, from: nil))
        cancelTracking()
        if activate { sendAction(action, to: target) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancelTracking() }
    }
    override func viewDidHide() { super.viewDidHide(); cancelTracking() }
    private func cancelTracking() {
        guard tracking else { return }
        tracking = false
        onTrackingChanged?(false)
    }
}
