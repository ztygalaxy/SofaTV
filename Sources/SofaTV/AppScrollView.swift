import AppKit

/// Application-wide native scrolling: overlay-only, with no reserved track.
class AppScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true
        hasHorizontalScroller = false
        verticalScroller = ChannelListScroller()
        verticalScroller?.controlSize = .small
        scrollerStyle = .overlay
        autohidesScrollers = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .overlay }
    }
}

/// Draw only a slim thumb; AppKit retains scrolling, dragging and overlay fading.
final class ChannelListScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 10 }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        var thumb = rect(for: .knob)
        guard thumb.width > 0, thumb.height > 0 else { return }
        thumb.origin.x = bounds.maxX - 8
        thumb.size.width = 5
        thumb = thumb.insetBy(dx: 0, dy: 1)
        guard thumb.height > 0 else { return }
        NSColor.labelColor.withAlphaComponent(hitPart == .knob ? 0.26 : 0.14).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 2.5, yRadius: 2.5).fill()
    }
}
