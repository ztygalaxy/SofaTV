import AppKit
import SwiftUI

struct ChannelListGroup: Equatable {
    let name: String
    let visibleChannelCount: Int
}

/// Float the existing header artwork above the flat List, avoiding native section chrome.
@MainActor final class ChannelListPinnedHeader: NSObject {
    private var groups: [ChannelListGroup] = []
    private var makeHeader: ((String) -> AnyView)?
    private weak var scrollView: NSScrollView?
    private weak var table: NSTableView?
    private var renderedGroup: String?
    private var cellInsets: [String: NSEdgeInsets] = [:]
    private var refreshPending = false
    private let viewport = Viewport()
    private let backdrop = Backdrop()
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    override init() {
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
            return
        }
        viewport.frame = scrollView.contentView.frame
        var row = 0
        var headers: [(group: ChannelListGroup, row: Int, rect: NSRect)] = []
        for group in groups {
            let rect = table.convert(table.rect(ofRow: row), to: viewport)
            headers.append((group, row, rect))
            if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false), cell.window === table.window {
                let cellRect = cell.convert(cell.bounds, to: viewport)
                cellInsets[group.name] = NSEdgeInsets(top: cellRect.minY - rect.minY, left: cellRect.minX - rect.minX,
                                                     bottom: rect.maxY - cellRect.maxY, right: rect.maxX - cellRect.maxX)
            }
            row += 1 + group.visibleChannelCount
        }
        guard let active = headers.lastIndex(where: { $0.rect.minY <= 0 }),
              let makeHeader else { viewport.isHidden = true; return }
        let current = headers[active]
        let height = current.rect.height
        guard height > 0 else { viewport.isHidden = true; return }
        let nextTop = active + 1 < headers.count ? headers[active + 1].rect.minY : CGFloat.infinity
        let offset = min(0, nextTop - height)
        // Preserve cell insets even after the original header is recycled offscreen.
        var cellRect = table.convert(table.frameOfCell(atColumn: 0, row: current.row), to: viewport)
        if let inset = cellInsets[current.group.name] {
            cellRect = NSRect(x: current.rect.minX + inset.left, y: current.rect.minY + inset.top,
                              width: current.rect.width - inset.left - inset.right,
                              height: current.rect.height - inset.top - inset.bottom)
        }
        backdrop.frame = NSRect(x: 0, y: offset, width: viewport.bounds.width, height: height)
        host.frame = NSRect(x: cellRect.minX, y: cellRect.minY - current.rect.minY, width: cellRect.width, height: cellRect.height)
        if renderedGroup != current.group.name {
            renderedGroup = current.group.name
            host.rootView = makeHeader(current.group.name)
        }
        viewport.isHidden = false
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
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.sofaBackground.setFill(); bounds.fill()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance(); needsDisplay = true
        }
    }
}
