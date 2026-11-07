import AppKit
import SwiftUI

@MainActor private final class OffscreenChannelWindow: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private struct ChannelListFixture: View {
    let channels: [Channel]
    let preview: ProgramGuidePreview
    let scale: CGFloat
    let presentation: ProgramGuidePreview.Presentation

    var body: some View {
        List {
            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                ChannelRow(channel: channel, isFavorite: false, isSelected: index == 0,
                           currentProgram: "12:00–13:00 当前节目", onPlay: {}, onFavorite: {},
                           onDeleteSource: { _ in }, onDelete: {}, contentScale: scale)
                    .equatable()
                    .onHover { preview.hover(channel, in: presentation, inside: $0) }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(ChannelRowHighlight(preview: preview, channel: channel.identity,
                                                          presentation: presentation, selected: index == 0))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.sofaBackground)
        .background { ChannelListScrollStyle() }
        .preferredColorScheme(.dark)
    }
}

@main struct ChannelRowChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let channels = (0..<12).map { Channel(name: "频道 \($0)", group: "测试", url: URL(string: "https://example.com/\($0)")!) }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        for scale: CGFloat in [1, 1.3] {
            let presentation: ProgramGuidePreview.Presentation = scale == 1 ? .embedded : .fullscreen
            let preview = ProgramGuidePreview(revealDelay: .zero, dismissDelay: .seconds(30))
            preview.setPresentation(presentation)
            let host = NSHostingView(rootView: ChannelListFixture(channels: channels, preview: preview, scale: scale, presentation: presentation))
            host.sizingOptions = []
            let window = OffscreenChannelWindow(contentRect: NSRect(x: -10000, y: -10000, width: 340, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderBack(nil)
            preview.hover(channels[1], in: presentation, inside: true)
            for _ in 0..<40 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            let table = views(host).compactMap { $0 as? NSTableView }.first!
            precondition(preview.channel == channels[1])
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let factor = CGFloat(bitmap.pixelsWide) / host.bounds.width
            func edgeColor(row: Int, right: Bool) -> NSColor {
                let point = host.convert(NSPoint(x: 0, y: table.rect(ofRow: row).midY), from: table)
                let y = Int((host.isFlipped ? point.y : host.bounds.maxY - point.y) * factor)
                let x = Int((right ? host.bounds.maxX - 2 : host.bounds.minX + 1) * factor)
                return bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            }
            for right in [false, true] {
                let playing = edgeColor(row: 0, right: right)
                let hovered = edgeColor(row: 1, right: right)
                let idle = edgeColor(row: 2, right: right)
                precondition(hovered.redComponent - idle.redComponent > 0.02, "Hover fill must reach both pane edges")
                if right {
                    precondition(playing.redComponent - idle.redComponent > 0.02, "Playing fill must reach the right edge")
                    precondition(abs(playing.redComponent - hovered.redComponent) < 0.015 && abs(playing.greenComponent - hovered.greenComponent) < 0.015 && abs(playing.blueComponent - hovered.blueComponent) < 0.015, "Playing and hovered rows must use the same grey fill")
                } else {
                    let accent = NSColor.sofaAccent.usingColorSpace(.deviceRGB)!
                    precondition(abs(playing.redComponent - accent.redComponent) < 0.12 && abs(playing.greenComponent - accent.greenComponent) < 0.12 && abs(playing.blueComponent - accent.blueComponent) < 0.12, "Only the playing channel must have a bright leading stripe")
                }
            }
            preview.hover(channels[1], in: presentation, inside: false)
            preview.hover(channels[3], in: presentation, inside: true)
            preview.hover(channels[3], in: presentation, inside: false)
            for _ in 0..<10 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            precondition(preview.channel == channels[1], "The previous programme preview must remain open during the hover delay")
            precondition(abs(edgeColor(row: 1, right: true).redComponent - edgeColor(row: 2, right: true).redComponent) < 0.015, "Leaving a row must immediately clear its hover fill even while its programme preview is still open")
            window.close()
            withExtendedLifetime((window, preview)) {}
        }
        print("Channel rows passed: matching grey fills, immediate hover and playing-only accent stripe through equatable wrappers at normal/fullscreen scales")
    }
}
