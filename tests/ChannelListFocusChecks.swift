import AppKit
import SwiftUI

@MainActor private final class FocusState: ObservableObject {
    let channels = (0..<120).map { Channel(name: String(format: "频道 %03d", $0), group: "分组 \($0 / 40)", url: URL(string: "https://example.com/\($0)")!) }
    @Published var search = ""
    @Published var favoritesOnly = false
    @Published var collapsedGroups = Set<String>()
    var favorites: Set<String> { Set(channels.prefix(3).map(\.id)) }
    var visibleChannels: [Channel] {
        channels.filter { (!favoritesOnly || favorites.contains($0.id)) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.group.localizedCaseInsensitiveContains(search)) }
    }
    var groups: [String] { Array(Set(visibleChannels.map(\.group))).sorted() }
    var rowIDs: [String?] {
        groups.flatMap { group -> [String?] in
            [nil] + (collapsedGroups.contains(group) ? [] : visibleChannels.filter { $0.group == group }.map { Optional($0.id) })
        }
    }
}

private struct Browser: View {
    @ObservedObject var state: FocusState
    let preview: ProgramGuidePreview
    let presentation: ProgramGuidePreview.Presentation
    var body: some View {
        List {
            ForEach(state.groups, id: \.self) { group in
                Text(group).frame(height: 28)
                if !state.collapsedGroups.contains(group) {
                    ForEach(state.visibleChannels.filter { $0.group == group }) { channel in
                        Text(channel.name).frame(height: 40)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
            }
        }
        .listStyle(.plain)
        .modifier(ChannelListFocus(preview: preview, presentation: presentation, favorites: state.favorites,
                                   search: $state.search, favoritesOnly: $state.favoritesOnly, collapsedGroups: $state.collapsedGroups))
    }
}

@MainActor private final class OffscreenPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@main struct ChannelListFocusChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let state = FocusState()
        let preview = ProgramGuidePreview()
        let normal = NSHostingView(rootView: Browser(state: state, preview: preview, presentation: .embedded))
        let fullscreen = NSHostingView(rootView: Browser(state: state, preview: preview, presentation: .fullscreen))
        normal.sizingOptions = []; fullscreen.sizingOptions = []
        normal.frame = NSRect(x: 0, y: 0, width: 280, height: 360)
        fullscreen.frame = NSRect(x: 300, y: 0, width: 340, height: 360)
        let panel = OffscreenPanel(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 360),
                                   styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        defer { panel.close() }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        panel.contentView = content
        content.addSubview(normal); content.addSubview(fullscreen)
        panel.orderBack(nil)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func table(in host: NSView) -> NSTableView { descendants(host).compactMap { $0 as? NSTableView }.first! }
        func settle() async throws {
            for _ in 0..<40 {
                content.layoutSubtreeIfNeeded()
                normal.layoutSubtreeIfNeeded(); fullscreen.layoutSubtreeIfNeeded()
                panel.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        func checkPosition(_ channel: Channel, in host: NSView, edge: String? = nil) {
            let table = table(in: host)
            let scroll = table.enclosingScrollView!
            let index = state.rowIDs.firstIndex(of: channel.id)!
            let row = table.rect(ofRow: index)
            let viewport = table.convert(scroll.contentView.bounds, from: scroll.contentView)
            precondition(viewport.intersects(row), "The playing channel must be visible: \(channel.name), row \(row), viewport \(viewport), search \(state.search), favorites \(state.favoritesOnly)")
            if edge == "top" {
                precondition(abs(scroll.contentView.bounds.minY) < 1, "First channel must stop at the natural top boundary")
            } else if edge == "bottom" {
                precondition(abs(viewport.maxY - table.bounds.maxY) < 2, "Last channel must stop at the natural bottom boundary")
            } else {
                precondition(abs(row.midY - viewport.midY) < 2, "Channel is not centered: row \(row), viewport \(viewport)")
            }
        }

        try await settle()
        let middle = state.channels[75]
        let inactiveOrigin = table(in: fullscreen).enclosingScrollView!.contentView.bounds.origin
        preview.showPlayingChannel(middle, in: .embedded)
        try await settle()
        checkPosition(middle, in: normal)
        precondition(table(in: fullscreen).enclosingScrollView!.contentView.bounds.origin == inactiveOrigin, "The hidden full-screen list must not scroll")

        let scroll = table(in: normal).enclosingScrollView!
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        preview.showPlayingChannel(middle, in: .embedded)
        try await settle()
        checkPosition(middle, in: normal)

        state.search = "频道 001"; state.favoritesOnly = true; state.collapsedGroups = [middle.group]
        try await settle()
        preview.showPlayingChannel(middle, in: .embedded)
        try await settle()
        precondition(state.search.isEmpty && !state.favoritesOnly && !state.collapsedGroups.contains(middle.group))
        checkPosition(middle, in: normal)

        state.search = "频道"; state.favoritesOnly = true
        try await settle()
        preview.showPlayingChannel(state.channels[1], in: .embedded)
        try await settle()
        precondition(state.search == "频道" && state.favoritesOnly, "Compatible search/favorites filters must remain in place")

        state.search = ""; state.favoritesOnly = false
        try await settle()
        for (channel, edge) in [(state.channels.first!, "top"), (state.channels.last!, "bottom")] {
            preview.showPlayingChannel(channel, in: .embedded)
            try await settle()
            checkPosition(channel, in: normal, edge: edge)
        }

        preview.setPresentation(.fullscreen)
        let normalOrigin = table(in: normal).enclosingScrollView!.contentView.bounds.origin
        preview.showPlayingChannel(middle, in: .fullscreen)
        try await settle()
        checkPosition(middle, in: fullscreen)
        precondition(table(in: normal).enclosingScrollView!.contentView.bounds.origin == normalOrigin, "Full-screen return must not scroll the hidden main list")
        print("Channel list focus passed: centered normal/fullscreen return, repeated requests, filters, collapsed groups, natural edges and presentation isolation")
    }
}
