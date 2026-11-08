import AppKit
import CoreText

/// Transparent playback controls, drawn above the video's own bottom gradient.
final class VideoVolumeControl: NSView {
    var onVolumeChanged: ((Float) -> Void)?
    var onToggleMute: (() -> Void)?
    var onReload: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var onPointerActivity: (() -> Void)?
    var onTrackingChanged: ((Bool) -> Void)?
    var onScroll: ((NSEvent) -> Void)?

    private enum Layout {
        static let size = NSSize(width: 336, height: 48)
        static let outerInset: CGFloat = 12
        static let buttonGap: CGFloat = 4
        static let visibleGap: CGFloat = 14
        static let speakerHitSide: CGFloat = 32
        static let speakerVisibleWidth: CGFloat = 20
        static let readoutHeight: CGFloat = 24
        static let sliderHeight: CGFloat = 32
        static let railHeight: CGFloat = 4
        static let knobDiameter: CGFloat = 10
    }

    private let reload = SymbolButton()
    private let speaker = SymbolButton()
    private let fullscreenButton = SymbolButton()
    private var fullscreenState: Bool?
    private let percentage = PercentageReadout()
    private let slider = VolumeSlider()
    private var pointerTrackingArea: NSTrackingArea?
    private var speakerSymbol: String?
    private var trackingBackground = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        reload.target = self; reload.action = #selector(reloadChannel)
        speaker.target = self; speaker.action = #selector(toggleMute)
        fullscreenButton.target = self; fullscreenButton.action = #selector(toggleFullscreen)
        addSubview(reload); addSubview(speaker); addSubview(slider); addSubview(percentage); addSubview(fullscreenButton)
        setAccessibilityElement(false)
        slider.onValueChanged = { [weak self] value in
            guard let self else { return }
            self.updateReadout(value, muted: false)
            self.onVolumeChanged?(value)
        }
        slider.onPointerActivity = { [weak self] in self?.onPointerActivity?() }
        slider.onTrackingChanged = { [weak self] tracking in self?.onTrackingChanged?(tracking) }
        slider.onScroll = { [weak self] event in self?.onScroll?(event) }
        reload.toolTip = "重新播放"; reload.setAccessibilityLabel("重新播放")
        if let url = Bundle.main.url(forResource: "yuanxunhuan", withExtension: "svg", subdirectory: "PlaybackControls"),
           let image = NSImage(contentsOf: url) {
            reload.setImage(image)
        } else {
            // Keep development builds usable when launched without the app bundle.
            reload.setSymbol("arrow.clockwise")
        }
        for button in [reload, speaker, fullscreenButton] {
            button.onPointerActivity = { [weak self] in self?.onPointerActivity?() }
            button.onTrackingChanged = { [weak self] tracking in self?.onTrackingChanged?(tracking) }
            button.onScroll = { [weak self] event in self?.onScroll?(event) }
        }
        setVolume(0.3); setFullscreen(false)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { Layout.size }
    static var buttonSide: CGFloat { Layout.speakerHitSide }
    static var trailingButtonCenterInset: CGFloat { Layout.outerInset + Layout.speakerHitSide / 2 }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setVolume(_ value: Float, muted: Bool = false) {
        let volume = value.isFinite ? min(1, max(0, value)) : 0
        let audibleVolume: Float = muted ? 0 : volume
        slider.setVolume(audibleVolume)
        updateReadout(audibleVolume, muted: muted)
    }
    @objc private func toggleMute() { onPointerActivity?(); onToggleMute?() }
    @objc private func reloadChannel() { onPointerActivity?(); onReload?() }
    @objc private func toggleFullscreen() { onPointerActivity?(); onToggleFullscreen?() }
    func setFullscreen(_ fullscreen: Bool) {
        guard fullscreenState != fullscreen else { return }
        fullscreenState = fullscreen
        let label = fullscreen ? "退出全屏" : "全屏播放"
        fullscreenButton.toolTip = label; fullscreenButton.setAccessibilityLabel(label)
        fullscreenButton.setSymbol(fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
    }
    private func updateReadout(_ value: Float, muted: Bool) {
        let previousWidth = percentage.inkWidth
        percentage.setPercentage(Int((value * 100).rounded()))
        if percentage.inkWidth != previousWidth { needsLayout = true }
        let label = (muted || value <= 0) ? "取消静音" : "静音"
        if speaker.toolTip != label {
            speaker.toolTip = label; speaker.setAccessibilityLabel(label)
        }
        let symbol = muted || value <= 0 ? "speaker.slash.fill" : value < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
        if speakerSymbol != symbol { speakerSymbol = symbol; speaker.setSymbol(symbol) }
    }
    override func layout() {
        super.layout()
        speaker.frame = NSRect(x: bounds.minX + Layout.outerInset, y: bounds.midY - Layout.speakerHitSide / 2,
                               width: Layout.speakerHitSide, height: Layout.speakerHitSide)
        // Use the painted icon edge, not the 32-point button's hit region.
        let railLeft = speaker.frame.midX + Layout.speakerVisibleWidth / 2 + Layout.visibleGap
        fullscreenButton.frame = NSRect(x: bounds.maxX - Layout.outerInset - Layout.speakerHitSide,
                                        y: bounds.midY - Layout.speakerHitSide / 2,
                                        width: Layout.speakerHitSide, height: Layout.speakerHitSide)
        reload.frame = NSRect(x: fullscreenButton.frame.minX - Layout.buttonGap - Layout.speakerHitSide,
                              y: bounds.midY - Layout.speakerHitSide / 2,
                              width: Layout.speakerHitSide, height: Layout.speakerHitSide)
        let readoutWidth = percentage.inkWidth
        let readoutX = reload.frame.midX - Layout.speakerVisibleWidth / 2 - Layout.visibleGap - readoutWidth
        percentage.frame = NSRect(x: readoutX, y: bounds.midY - Layout.readoutHeight / 2,
                                  width: readoutWidth, height: Layout.readoutHeight)
        slider.frame = NSRect(x: railLeft, y: bounds.midY - Layout.sliderHeight / 2,
                              width: max(0, readoutX - Layout.visibleGap - railLeft), height: Layout.sliderHeight)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self)
        addTrackingArea(area); pointerTrackingArea = area
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { reload.cancelTracking(); speaker.cancelTracking(); fullscreenButton.cancelTracking(); slider.cancelTracking(); endBackgroundTracking() }
    }
    override func mouseEntered(with event: NSEvent) { onPointerActivity?() }
    override func mouseMoved(with event: NSEvent) { onPointerActivity?() }
    override func mouseDown(with event: NSEvent) {
        onPointerActivity?()
        if !trackingBackground { trackingBackground = true; onTrackingChanged?(true) }
    }
    override func mouseDragged(with event: NSEvent) { onPointerActivity?() }
    override func mouseUp(with event: NSEvent) { onPointerActivity?(); endBackgroundTracking() }
    private func endBackgroundTracking() {
        guard trackingBackground else { return }
        trackingBackground = false; onTrackingChanged?(false)
    }
    override func rightMouseDown(with event: NSEvent) { onPointerActivity?() }
    override func rightMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) { onPointerActivity?(); onScroll?(event) }

    /// The native button keeps target/action and accessibility activation semantics.
    final class SymbolButton: NSButton {
        var onPointerActivity: (() -> Void)?
        var onTrackingChanged: ((Bool) -> Void)?
        var onScroll: ((NSEvent) -> Void)?
        private var tracking = false
        private var hovering = false
        private var icon: NSImage?
        private var pointerTrackingArea: NSTrackingArea?
        private static var icons: [String: NSImage] = [:]

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            title = ""; isBordered = false; imagePosition = .imageOnly
            setButtonType(.momentaryChange); focusRingType = .none
            setAccessibilityRole(.button)
        }
        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var acceptsFirstResponder: Bool { false }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var isEnabled: Bool {
            didSet {
                guard oldValue != isEnabled else { return }
                if !isEnabled { cancelTracking() }
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
            }
        }

        func setSymbol(_ name: String, rotation: CGFloat = 0) {
            let key = "\(name):\(rotation)"
            if let cached = Self.icons[key] { icon = cached }
            else if let rendered = Self.renderSymbol(name, rotation: rotation) { Self.icons[key] = rendered; icon = rendered }
            needsDisplay = true
        }
        func setImage(_ image: NSImage) {
            // Imported SVGs often include transparent view-box padding, while
            // SF Symbols below are cropped to their ink bounds. Trim the SVG
            // the same way so all three playback icons share a visual size.
            icon = Self.trimTransparentPadding(from: image) ?? image
            needsDisplay = true
        }
        private static func trimTransparentPadding(from image: NSImage) -> NSImage? {
            let scale: CGFloat = 4
            let width = max(1, Int(ceil(image.size.width * scale)))
            let height = max(1, Int(ceil(image.size.height * scale)))
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap), let pixels = bitmap.bitmapData else { return nil }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            let rect = NSRect(x: 0, y: 0, width: width, height: height)
            context.cgContext.clear(rect)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where pixels[y * bitmap.bytesPerRow + x * 4 + 3] > 0 {
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY,
                  let cropped = bitmap.cgImage?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return nil }
            return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        }
        private static func renderSymbol(_ name: String, rotation: CGFloat) -> NSImage? {
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)) else { return nil }
            // Crop after rotating so the painted outline fits the same 20-point icon size.
            let scale: CGFloat = 4
            let symbolWidth = ceil(symbol.size.width * scale)
            let symbolHeight = ceil(symbol.size.height * scale)
            let radians = rotation * .pi / 180
            let width = max(1, Int(ceil(abs(symbolWidth * cos(radians)) + abs(symbolHeight * sin(radians)))))
            let height = max(1, Int(ceil(abs(symbolWidth * sin(radians)) + abs(symbolHeight * cos(radians)))))
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap), let pixels = bitmap.bitmapData else { return nil }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            let rect = NSRect(x: 0, y: 0, width: width, height: height)
            context.cgContext.clear(rect)
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            context.cgContext.rotate(by: radians)
            symbol.draw(in: NSRect(x: -symbolWidth / 2, y: -symbolHeight / 2, width: symbolWidth, height: symbolHeight), from: .zero, operation: .sourceOver, fraction: 1)
            context.cgContext.restoreGState()
            NSColor.white.withAlphaComponent(0.94).setFill(); rect.fill(using: .sourceIn)
            NSGraphicsContext.restoreGraphicsState()
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where pixels[y * bitmap.bytesPerRow + x * 4 + 3] > 0 {
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY,
                  let image = bitmap.cgImage?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        override func draw(_ dirtyRect: NSRect) {
            if hovering && isEnabled {
                NSColor.white.withAlphaComponent(tracking ? 0.18 : 0.10).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
            }
            guard let icon else { return }
            let scale = Layout.speakerVisibleWidth / max(1, max(icon.size.width, icon.size.height))
            let width = icon.size.width * scale
            let height = icon.size.height * scale
            let rect = NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.4, respectFlipped: true, hints: nil)
        }
        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            onPointerActivity?()
            hovering = true; needsDisplay = true
            if !tracking { tracking = true; onTrackingChanged?(true) }
        }
        override func mouseDragged(with event: NSEvent) {
            if tracking {
                hovering = bounds.contains(convert(event.locationInWindow, from: nil)); needsDisplay = true
                onPointerActivity?()
            }
        }
        override func mouseUp(with event: NSEvent) {
            guard tracking else { return }
            onPointerActivity?()
            let activate = isEnabled && !isHiddenOrHasHiddenAncestor && bounds.contains(convert(event.locationInWindow, from: nil))
            cancelTracking()
            if activate { sendAction(action, to: target) }
        }
        func cancelTracking() {
            guard tracking else { return }
            tracking = false; needsDisplay = true; onTrackingChanged?(false)
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { cancelTracking(); hovering = false } }
        override func viewDidHide() { super.viewDidHide(); cancelTracking(); hovering = false }
        override func rightMouseDown(with event: NSEvent) { onPointerActivity?() }
        override func rightMouseUp(with event: NSEvent) {}
        override func scrollWheel(with event: NSEvent) { onPointerActivity?(); onScroll?(event) }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
            let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self)
            addTrackingArea(area); pointerTrackingArea = area
        }
        override func resetCursorRects() { addCursorRect(visibleRect, cursor: isEnabled ? .pointingHand : .arrow) }
        override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true; onPointerActivity?() }
        override func mouseMoved(with event: NSEvent) { onPointerActivity?() }
        override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    }

    /// Draw using actual glyph bounds, avoiding NSTextField's invisible cell padding.
    private final class PercentageReadout: NSView {
        private var text = ""
        private var line: CTLine?
        private var inkBounds: CGRect {
            guard let line else { return .zero }
            return CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        }
        var inkWidth: CGFloat { ceil(inkBounds.width) }
        override init(frame frameRect: NSRect) { super.init(frame: frameRect); setAccessibilityElement(false) }
        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func setPercentage(_ value: Int) {
            let text = "\(value)%"
            guard text != self.text else { return }
            self.text = text
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.94)
            ])
            line = CTLineCreateWithAttributedString(attributed)
            needsDisplay = true
        }
        override func draw(_ dirtyRect: NSRect) {
            guard let line, let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState(); context.textMatrix = .identity; context.textPosition = .zero
            let ink = inkBounds
            context.textPosition = CGPoint(x: bounds.maxX - ink.maxX, y: bounds.midY - ink.midY)
            CTLineDraw(line, context); context.restoreGState()
        }
    }

    /// Native event delivery keeps drags nonblocking and routes the release back here.
    private final class VolumeSlider: NSControl {
        var onValueChanged: ((Float) -> Void)?
        var onPointerActivity: (() -> Void)?
        var onTrackingChanged: ((Bool) -> Void)?
        var onScroll: ((NSEvent) -> Void)?
        private var volume: Float = 0.3
        private var tracking = false
        private var trackingWidth: CGFloat?
        private var pointerTrackingArea: NSTrackingArea?
        private var knobRadius: CGFloat { Layout.knobDiameter / 2 }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            focusRingType = .none
            setAccessibilityElement(true); setAccessibilityRole(.slider)
            setAccessibilityLabel("视频音量"); setAccessibilityHelp("拖动或滚动调节音量")
        }
        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var acceptsFirstResponder: Bool { isEnabled }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        func setVolume(_ value: Float) { assign(value, notify: false) }
        private func assign(_ value: Float, notify: Bool) {
            let newValue = value.isFinite ? min(1, max(0, value)) : 0
            guard newValue != volume else { return }
            volume = newValue; needsDisplay = true
            NSAccessibility.post(element: self, notification: .valueChanged)
            if notify { onValueChanged?(newValue) }
        }
        private func updateVolume(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            // A change in digit count can resize the rail. Keep a drag's input
            // range fixed so crossing 9/10 or 99/100 cannot make its value jump.
            let trackWidth = max(1, (trackingWidth ?? bounds.width) - 2 * knobRadius)
            assign(Float((point.x - knobRadius) / trackWidth), notify: true)
        }
        func cancelTracking() {
            guard tracking else { return }
            tracking = false; trackingWidth = nil; onTrackingChanged?(false)
        }
        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            onPointerActivity?(); window?.makeFirstResponder(self)
            if !tracking { tracking = true; trackingWidth = bounds.width; onTrackingChanged?(true) }
            updateVolume(with: event)
        }
        override func mouseDragged(with event: NSEvent) {
            guard tracking else { return }
            onPointerActivity?(); updateVolume(with: event)
        }
        override func mouseUp(with event: NSEvent) {
            guard tracking else { return }
            onPointerActivity?(); updateVolume(with: event); cancelTracking()
        }
        override func rightMouseDown(with event: NSEvent) { onPointerActivity?() }
        override func rightMouseUp(with event: NSEvent) {}
        override func scrollWheel(with event: NSEvent) { onPointerActivity?(); onScroll?(event) }
        override func keyDown(with event: NSEvent) {
            guard isEnabled else { return }
            switch event.keyCode {
            case 123, 125: onPointerActivity?(); assign(volume - 0.05, notify: true)
            case 124, 126: onPointerActivity?(); assign(volume + 0.05, notify: true)
            default: super.keyDown(with: event)
            }
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
            let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self)
            addTrackingArea(area); pointerTrackingArea = area
        }
        override func resetCursorRects() { addCursorRect(visibleRect, cursor: .arrow) }
        override func mouseEntered(with event: NSEvent) { onPointerActivity?() }
        override func mouseMoved(with event: NSEvent) { onPointerActivity?() }
        override func draw(_ dirtyRect: NSRect) {
            // The rail occupies the entire painted width; the knob never extends beyond it.
            let width = max(0, bounds.width)
            let rail = NSRect(x: bounds.minX, y: bounds.midY - Layout.railHeight / 2, width: width, height: Layout.railHeight)
            NSColor.white.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: rail, xRadius: Layout.railHeight / 2, yRadius: Layout.railHeight / 2).fill()
            let fill = NSRect(x: rail.minX, y: rail.minY, width: CGFloat(volume) * width, height: rail.height)
            NSColor.white.withAlphaComponent(0.94).setFill()
            NSBezierPath(roundedRect: fill, xRadius: Layout.railHeight / 2, yRadius: Layout.railHeight / 2).fill()
            let position = bounds.minX + knobRadius + CGFloat(volume) * max(0, width - Layout.knobDiameter)
            NSBezierPath(ovalIn: NSRect(x: position - knobRadius, y: bounds.midY - knobRadius,
                                      width: Layout.knobDiameter, height: Layout.knobDiameter)).fill()
        }
        override func accessibilityValue() -> Any? { NSNumber(value: volume) }
        override func accessibilityValueDescription() -> String? { "\(Int((volume * 100).rounded()))%" }
        override func accessibilityMinValue() -> Any? { NSNumber(value: 0) }
        override func accessibilityMaxValue() -> Any? { NSNumber(value: 1) }
        override func setAccessibilityValue(_ value: Any?) {
            guard isEnabled, let number = value as? NSNumber else { return }
            onPointerActivity?(); assign(number.floatValue, notify: true)
        }
        override func accessibilityPerformIncrement() -> Bool {
            guard isEnabled else { return false }
            onPointerActivity?(); assign(volume + 0.05, notify: true); return true
        }
        override func accessibilityPerformDecrement() -> Bool {
            guard isEnabled else { return false }
            onPointerActivity?(); assign(volume - 0.05, notify: true); return true
        }
    }
}
