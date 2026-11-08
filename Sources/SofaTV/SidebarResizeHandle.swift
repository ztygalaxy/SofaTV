import AppKit
import SwiftUI

/// The divider keeps its original one-point layout. Its transparent overlay
/// catches a nearby drag without adding a gutter or moving either pane.
struct SidebarResizeHandle: View {
    static let dividerWidth: CGFloat = 1
    static let hitWidth: CGFloat = 7
    static let hitExtension: CGFloat = (hitWidth - dividerWidth) / 2
    @Binding var width: CGFloat
    let visibleWidth: CGFloat
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    var onCommit: () -> Void = {}
    var isActive = true

    var body: some View {
        Color.clear.frame(width: Self.dividerWidth)
            .overlay {
                if isActive {
                    NativeHandle(width: $width, visibleWidth: visibleWidth, minimumWidth: minimumWidth,
                                 maximumWidth: maximumWidth, onCommit: onCommit)
                        .frame(width: Self.hitWidth)
                }
            }
    }
    private struct NativeHandle: NSViewRepresentable {
        @Binding var width: CGFloat
        let visibleWidth: CGFloat
        let minimumWidth: CGFloat
        let maximumWidth: CGFloat
        let onCommit: () -> Void
        func makeNSView(context: Context) -> Handle { Handle() }
        func updateNSView(_ view: Handle, context: Context) {
            view.visibleWidth = visibleWidth
            view.minimumWidth = minimumWidth; view.maximumWidth = maximumWidth
            view.onChange = { width = $0 }; view.onCommit = onCommit
        }
        static func dismantleNSView(_ view: Handle, coordinator: ()) { view.cancelDrag() }
    }

    final class Handle: NSView {
        var visibleWidth: CGFloat = 294
        var minimumWidth: CGFloat = 294
        var maximumWidth: CGFloat = 600
        var onChange: ((CGFloat) -> Void)?
        var onCommit: (() -> Void)?
        private var dragStart: (x: CGFloat, width: CGFloat)?
        private weak var dragWindow: NSWindow?
        private var hovering = false
        private var area: NSTrackingArea?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            setAccessibilityElement(true); setAccessibilityRole(.splitter)
            setAccessibilityLabel("调整频道列表宽度")
            toolTip = "左右拖动调整频道列表宽度"
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var isOpaque: Bool { false }
        override var acceptsFirstResponder: Bool { false }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(visibleRect, cursor: .resizeLeftRight) }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self)
            addTrackingArea(next); area = next
        }
        override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
        override func mouseDown(with event: NSEvent) {
            guard dragStart == nil, let window else { return }
            dragStart = (event.locationInWindow.x, visibleWidth)
            dragWindow = window
            window.disableCursorRects()
            NSCursor.resizeLeftRight.push()
            for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(interruptDrag), name: name, object: window)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(interruptDrag), name: NSApplication.didResignActiveNotification, object: nil)
            needsDisplay = true
        }
        override func mouseDragged(with event: NSEvent) {
            guard let dragStart else { return }
            // The handle moves during layout; window coordinates stay fixed.
            change(dragStart.width + event.locationInWindow.x - dragStart.x)
        }
        override func mouseUp(with event: NSEvent) {
            guard dragStart != nil else { return }
            mouseDragged(with: event)
            cancelDrag()
        }
        func cancelDrag() {
            guard dragStart != nil else { return }
            dragStart = nil; needsDisplay = true
            NotificationCenter.default.removeObserver(self)
            NSCursor.pop()
            dragWindow?.enableCursorRects()
            if let view = dragWindow?.contentView { dragWindow?.invalidateCursorRects(for: view) }
            dragWindow = nil
            onCommit?()
        }
        @objc private func interruptDrag() { cancelDrag(); hovering = false; needsDisplay = true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { cancelDrag(); hovering = false }
        }
        override func viewDidHide() { super.viewDidHide(); cancelDrag(); hovering = false }
        private func change(_ proposed: CGFloat) {
            let value = min(max(proposed, minimumWidth), maximumWidth)
            guard value != visibleWidth else { return }
            visibleWidth = value; onChange?(value)
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        override func draw(_ dirtyRect: NSRect) {
            let thickness: CGFloat = hovering || dragStart != nil ? 3 : Self.normalLineWidth
            NSColor.separatorColor.setFill()
            NSRect(x: bounds.midX - thickness / 2, y: bounds.minY, width: thickness, height: bounds.height).fill()
        }
        private static let normalLineWidth: CGFloat = 1
        override func accessibilityValue() -> Any? { NSNumber(value: Double(visibleWidth)) }
        override func accessibilityValueDescription() -> String? { "\(Int(visibleWidth)) 点" }
        override func accessibilityMinValue() -> Any? { NSNumber(value: Double(minimumWidth)) }
        override func accessibilityMaxValue() -> Any? { NSNumber(value: Double(maximumWidth)) }
        override func accessibilityPerformIncrement() -> Bool { change(visibleWidth + 20); onCommit?(); return true }
        override func accessibilityPerformDecrement() -> Bool { change(visibleWidth - 20); onCommit?(); return true }
    }
}
