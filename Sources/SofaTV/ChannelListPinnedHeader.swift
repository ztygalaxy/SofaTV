import AppKit
import QuartzCore
import SwiftUI

struct ChannelListGroup: Equatable {
    let name: String
    let visibleChannelCount: Int
}

/// Float the existing header artwork above the flat List, avoiding native section chrome.
@MainActor final class ChannelListPinnedHeader: NSObject {
    private var groups: [ChannelListGroup] = []
    var hasGroups: Bool { !groups.isEmpty }
    private var makeHeader: ((String) -> AnyView)?
    private weak var scrollView: NSScrollView?
    private weak var table: NSTableView?
    private var renderedGroup: String?
    private var cellInsets: [String: NSEdgeInsets] = [:]
    private var refreshPending = false
    private let viewport = Viewport()
    private let backdrop: Backdrop
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private let clipsContentBehindHeader: Bool
    private let contentMask = CAShapeLayer()
    private var originalContentMask: CALayer?

    init(backdropColor: NSColor = .sofaBackground, clipsContentBehindHeader: Bool = false) {
        backdrop = Backdrop(color: backdropColor)
        self.clipsContentBehindHeader = clipsContentBehindHeader
        super.init()
        viewport.wantsLayer = true; viewport.layer?.masksToBounds = true
        viewport.addSubview(backdrop); backdrop.addSubview(host)
        host.sizingOptions = []
        viewport.isHidden = true
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    func update(groups: [ChannelListGroup], makeHeader: @escaping (String) -> AnyView) {
        if self.groups != groups { renderedGroup = nil }
        self.groups = groups; self.makeHeader = makeHeader
        scheduleRefresh()
    }
    func redisplay() {
        renderedGroup = nil
        host.needsLayout = true; host.needsDisplay = true
        scheduleRefresh()
    }
    func attach(to scroll: NSScrollView) {
        guard let table = scroll.documentView as? NSTableView else { detach(); return }
        if scrollView !== scroll || self.table !== table {
            detach()
            scrollView = scroll; self.table = table
            scroll.addSubview(viewport, positioned: .above, relativeTo: scroll.contentView)
            scroll.contentView.postsBoundsChangedNotifications = true
            table.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(viewportDidScroll), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(documentDidResize), name: NSView.frameDidChangeNotification, object: table)
        }
        refresh()
    }
    func detach() {
        NotificationCenter.default.removeObserver(self)
        restoreContentMask()
        viewport.removeFromSuperview(); viewport.isHidden = true
        scrollView = nil; table = nil; renderedGroup = nil; cellInsets.removeAll()
    }
    @objc private func viewportDidScroll() { refresh() }
    @objc private func documentDidResize() { scheduleRefresh() }
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false; self.refresh()
        }
    }
    private func refresh() {
        guard let scrollView, let table, scrollView.window != nil, !groups.isEmpty,
              table.numberOfRows == groups.reduce(0, { $0 + 1 + $1.visibleChannelCount }) else {
            viewport.isHidden = true
            restoreContentMask()
            return
        }
        viewport.frame = scrollView.contentView.frame
        var row = 0
        var headers: [(group: ChannelListGroup, row: Int, rect: NSRect)] = []
        for group in groups {
            let rect = table.convert(table.rect(ofRow: row), to: viewport)
            headers.append((group, row, rect))
            if !clipsContentBehindHeader,
               let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false), cell.window === table.window {
                let cellRect = cell.convert(cell.bounds, to: viewport)
                // Recycled cells can briefly be empty or retain another row's
                // frame. Never let those transient sizes replace valid insets.
                if cellRect.width > 0, cellRect.height >= rect.height * 0.5,
                   rect.insetBy(dx: -1, dy: -1).contains(cellRect) {
                    cellInsets[group.name] = NSEdgeInsets(top: cellRect.minY - rect.minY, left: cellRect.minX - rect.minX,
                                                         bottom: rect.maxY - cellRect.maxY, right: rect.maxX - cellRect.maxX)
                }
            }
            row += 1 + group.visibleChannelCount
        }
        guard let active = headers.lastIndex(where: { $0.rect.minY <= 0 }),
              let makeHeader else { viewport.isHidden = true; restoreContentMask(); return }
        let current = headers[active]
        let height = current.rect.height
        guard height > 0 else { viewport.isHidden = true; restoreContentMask(); return }
        let nextTop = active + 1 < headers.count ? headers[active + 1].rect.minY : CGFloat.infinity
        let offset = min(0, nextTop - height)
        backdrop.frame = NSRect(x: 0, y: offset, width: viewport.bounds.width, height: height)
        // Full-screen headers have zero row insets and fill their own backdrop.
        // Their geometry must not depend on a virtualized table cell's lifetime.
        var headerFrame = backdrop.bounds
        if !clipsContentBehindHeader, let inset = cellInsets[current.group.name] {
            headerFrame = NSRect(x: inset.left, y: inset.top,
                                 width: current.rect.width - inset.left - inset.right,
                                 height: height - inset.top - inset.bottom)
        }
        if renderedGroup != current.group.name {
            renderedGroup = current.group.name
            host.rootView = makeHeader(current.group.name)
        }
        host.frame = headerFrame
        host.needsLayout = true; host.needsDisplay = true
        clipContent(coveredHeight: max(0, height + offset))
        viewport.isHidden = false
    }

    /// The drawer already blurs the video. Remove table pixels beneath its
    /// floating header instead of adding a second material that blurs the rows
    /// and builds up an almost opaque grey strip.
    private func clipContent(coveredHeight: CGFloat) {
        guard clipsContentBehindHeader, let clip = scrollView?.contentView else { return }
        guard coveredHeight > 0 else { restoreContentMask(); return }
        clip.wantsLayer = true
        guard let layer = clip.layer else { return }
        if layer.mask !== contentMask { originalContentMask = layer.mask }
        let size = clip.bounds.size
        let height = min(size.height, coveredHeight)
        let visible = CGRect(x: 0, y: clip.isFlipped ? height : 0,
                             width: size.width, height: max(0, size.height - height))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        contentMask.frame = layer.bounds
        contentMask.path = CGPath(rect: visible, transform: nil)
        contentMask.fillColor = NSColor.white.cgColor
        layer.mask = contentMask
        CATransaction.commit()
    }

    private func restoreContentMask() {
        guard let layer = scrollView?.contentView.layer, layer.mask === contentMask else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.mask = originalContentMask
        CATransaction.commit()
        originalContentMask = nil
    }

    private final class Viewport: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            let localPoint = convert(point, from: superview)
            guard let header = subviews.first, !isHidden, bounds.contains(localPoint), header.frame.contains(localPoint) else { return nil }
            return super.hitTest(point)
        }
    }
    private final class Backdrop: NSView {
        private let color: NSColor
        init(color: NSColor) { self.color = color; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            color.setFill(); bounds.fill()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance(); needsDisplay = true
        }
    }
}
