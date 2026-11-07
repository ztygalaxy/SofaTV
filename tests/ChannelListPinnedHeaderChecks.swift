import AppKit
import SwiftUI

/// Model the zero-size cell AppKit exposes while a list row is being recycled.
@MainActor private final class HeaderTable: NSTableView {
    let sampledHeader = NSView()
    override func view(atColumn column: Int, row: Int, makeIfNecessary flag: Bool) -> NSView? {
        row == 0 ? sampledHeader : nil
    }
}

@MainActor private final class Rows: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 6 }
}

@main struct ChannelListPinnedHeaderChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 100), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        let table = HeaderTable(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let rows = Rows()
        table.dataSource = rows
        table.headerView = nil
        table.rowHeight = 40
        table.intercellSpacing = .zero
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("channel"))
        column.width = 320
        table.addTableColumn(column)
        scroll.documentView = table
        window.contentView = scroll
        table.reloadData()
        table.addSubview(table.sampledHeader)
        window.contentView?.layoutSubtreeIfNeeded()

        let groups = [ChannelListGroup(name: "A", visibleChannelCount: 2), ChannelListGroup(name: "B", visibleChannelCount: 2)]
        let header = ChannelListPinnedHeader(backdropColor: .clear, clipsContentBehindHeader: true)
        header.update(groups: groups) { AnyView(Text($0)) }

        func hostingView(in view: NSView) -> NSHostingView<AnyView>? {
            if let host = view as? NSHostingView<AnyView> { return host }
            return view.subviews.lazy.compactMap { hostingView(in: $0) }.first
        }
        func checkVisibleHeader() {
            guard let host = hostingView(in: scroll) else { preconditionFailure("Missing floating header") }
            precondition(!host.isHiddenOrHasHiddenAncestor, "Header must be visible after returning")
            precondition(host.frame.height == 40 && host.frame.width > 0, "Recycled cells must not collapse the header")
            precondition(scroll.contentView.layer?.mask != nil, "Rows behind the glass header must remain masked")
        }

        scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 0).minY))
        table.sampledHeader.frame = table.rect(ofRow: 0)
        header.attach(to: scroll)
        checkVisibleHeader()

        table.sampledHeader.frame = .zero
        header.attach(to: scroll)
        checkVisibleHeader()
        header.detach()
        precondition(scroll.contentView.layer?.mask == nil, "Detaching must restore the content mask")
        header.attach(to: scroll)
        checkVisibleHeader()

        for _ in 0..<30 {
            scroll.isHidden = true
            table.sampledHeader.frame = .zero
            header.redisplay()
            scroll.isHidden = false
            header.attach(to: scroll)
            checkVisibleHeader()

            scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 3).minY + 1))
            header.attach(to: scroll)
            checkVisibleHeader()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 0).minY))
            header.attach(to: scroll)
            checkVisibleHeader()
        }
        header.detach()

        // The normal sidebar must also ignore an empty sampled cell rather than
        // caching a zero-height header after previously seeing a healthy cell.
        let solidHeader = ChannelListPinnedHeader()
        solidHeader.update(groups: groups) { AnyView(Text($0)) }
        table.sampledHeader.frame = table.rect(ofRow: 0)
        solidHeader.attach(to: scroll)
        table.sampledHeader.frame = .zero
        solidHeader.attach(to: scroll)
        precondition(hostingView(in: scroll)?.frame.height == 40)
        precondition(scroll.contentView.layer?.mask == nil)
        solidHeader.detach()

        withExtendedLifetime((window, rows)) {}
        print("Pinned header checks passed: recycled cells, detach/reattach, 30 hide/show and scroll-return cycles, and normal sidebar")
    }
}
