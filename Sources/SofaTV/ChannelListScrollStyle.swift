import AppKit
import QuartzCore
import SwiftUI

/// Keep the channel list's scrollbar quiet without changing system preferences.
struct ChannelListScrollStyle: NSViewRepresentable {
    var groups: [ChannelListGroup] = []
    var makeHeader: (String) -> AnyView = { _ in AnyView(EmptyView()) }
    var pinnedHeaderBackground: NSColor = .sofaBackground
    var clipsContentBehindHeader = false

    func makeNSView(context: Context) -> Probe {
        let view = Probe(pinnedHeaderBackground: pinnedHeaderBackground, clipsContentBehindHeader: clipsContentBehindHeader)
        view.pinnedHeader.update(groups: groups, makeHeader: makeHeader)
        return view
    }
    func updateNSView(_ view: Probe, context: Context) {
        view.pinnedHeader.update(groups: groups, makeHeader: makeHeader)
        view.scheduleConfiguration()
    }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: NSView {
        let pinnedHeader: ChannelListPinnedHeader
        private weak var styledScrollView: NSScrollView?
        private weak var observedStyleScrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?
        private var applyingScrollerStyle = false
        private var configurationPending = false

        init(pinnedHeaderBackground: NSColor, clipsContentBehindHeader: Bool) {
            pinnedHeader = ChannelListPinnedHeader(backdropColor: pinnedHeaderBackground, clipsContentBehindHeader: clipsContentBehindHeader)
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleConfiguration() }
        override func viewDidUnhide() {
            super.viewDidUnhide()
            pinnedHeader.redisplay()
            scheduleConfiguration()
        }
        deinit { NotificationCenter.default.removeObserver(self) }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() }
            NotificationCenter.default.removeObserver(self, name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
            if window != nil {
                NotificationCenter.default.addObserver(self, selector: #selector(scrollerPreferenceChanged), name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
            }
            scheduleConfiguration()
        }
        @objc private func scrollerPreferenceChanged() { scheduleConfiguration() }
        override func layout() { super.layout(); scheduleConfiguration() }

        func scheduleConfiguration() {
            guard window != nil, !configurationPending else { return }
            configurationPending = true
            // SwiftUI can attach the list's scroll view after its background probe.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.configurationPending = false
                self.configureScrollView()
            }
        }
        private func configureScrollView() {
            guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
            if let scroll = styledScrollView, matches(scroll) { configure(scroll); return }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = findScrollView(in: view) {
                    styledScrollView = scroll
                    configure(scroll)
                    return
                }
                ancestor = view.superview
            }
        }
        private func findScrollView(in view: NSView) -> NSScrollView? {
            if view === self { return nil }
            if let scroll = view as? NSScrollView, matches(scroll) { return scroll }
            for child in view.subviews {
                if let scroll = findScrollView(in: child) { return scroll }
            }
            return nil
        }
        private func matches(_ scroll: NSScrollView) -> Bool {
            guard scroll.window === window else { return false }
            let frame = scroll.convert(scroll.bounds, to: self)
            // An overlay also intersects the larger video scroll view beneath it.
            // Match the pane's size as well as its position before applying the style.
            guard abs(frame.width - bounds.width) <= max(2, bounds.width * 0.08),
                  abs(frame.height - bounds.height) <= max(2, bounds.height * 0.08) else { return false }
            let overlap = bounds.intersection(frame)
            return !overlap.isNull && overlap.width > bounds.width * 0.8 && overlap.height > bounds.height * 0.8
        }
        func detach() {
            styleObservation?.invalidate(); styleObservation = nil
            observedStyleScrollView = nil; styledScrollView = nil
            pinnedHeader.detach()
        }
        private func observeScrollerStyle(_ scroll: NSScrollView) {
            guard observedStyleScrollView !== scroll else { return }
            styleObservation?.invalidate()
            observedStyleScrollView = scroll
            styleObservation = scroll.observe(\.scrollerStyle) { [weak self] scroll, _ in
                // AppKit changes this property on the main thread. Correct it before
                // this layout transaction can display a narrower, legacy viewport.
                MainActor.assumeIsolated {
                    guard let self, self.observedStyleScrollView === scroll else { return }
                    self.preserveOverlay(in: scroll)
                }
            }
        }
        private func preserveOverlay(in scroll: NSScrollView) {
            guard !applyingScrollerStyle, scroll.scrollerStyle != .overlay else { return }
            applyingScrollerStyle = true
            defer { applyingScrollerStyle = false }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            scroll.scrollerStyle = .overlay
            CATransaction.commit()
        }
        private func configure(_ scroll: NSScrollView) {
            observeScrollerStyle(scroll)
            if !(scroll.verticalScroller is ChannelListScroller) {
                let previous = scroll.verticalScroller
                let scroller = ChannelListScroller(frame: previous?.frame ?? .zero)
                scroller.controlSize = .small
                scroller.target = previous?.target; scroller.action = previous?.action
                scroller.doubleValue = previous?.doubleValue ?? 0
                scroller.knobProportion = previous?.knobProportion ?? 1
                scroll.verticalScroller = scroller
            }
            preserveOverlay(in: scroll)
            if !scroll.autohidesScrollers { scroll.autohidesScrollers = true }
            if pinnedHeader.hasGroups { pinnedHeader.attach(to: scroll) }
            else { pinnedHeader.detach() }
        }
    }
}

extension View {
    /// Reuse the channel/guide scrollbar without adding group headers.
    func appScrollStyle() -> some View { background(ChannelListScrollStyle()) }
}
