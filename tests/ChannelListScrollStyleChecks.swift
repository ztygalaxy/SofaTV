import AppKit

@main struct ChannelListScrollStyleChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        window.contentView = root
        func scroll(_ rect: NSRect) -> NSScrollView {
            let view = NSScrollView(frame: rect)
            view.hasVerticalScroller = true
            view.scrollerStyle = .legacy
            view.documentView = NSView(frame: NSRect(x: 0, y: 0, width: rect.width, height: 1600))
            root.addSubview(view)
            return view
        }
        let video = scroll(NSRect(x: 300, y: 0, width: 700, height: 600))
        let channels = scroll(NSRect(x: 0, y: 0, width: 294, height: 500))
        let guideFrame = NSRect(x: 300, y: 50, width: 260, height: 500)
        let guide = scroll(guideFrame)
        let probe = ChannelListScrollStyle.Probe(pinnedHeaderBackground: .clear, clipsContentBehindHeader: false)
        probe.frame = guideFrame
        root.addSubview(probe)
        func settle() async throws {
            probe.scheduleConfiguration()
            for _ in 0..<10 { try await Task.sleep(for: .milliseconds(10)) }
        }
        try await settle()
        precondition(guide.verticalScroller is ChannelListScroller && guide.scrollerStyle == .overlay,
                     "The overlapping video scroll view must not steal the guide's style")
        precondition(video.scrollerStyle == .legacy && !(video.verticalScroller is ChannelListScroller))
        precondition(channels.scrollerStyle == .legacy && !(channels.verticalScroller is ChannelListScroller))
        guide.scrollerStyle = .legacy
        precondition(guide.scrollerStyle == .overlay, "AppKit preference changes must not restore the wide track")
        guide.verticalScroller = NSScroller()
        try await settle()
        precondition(guide.verticalScroller is ChannelListScroller)
        guide.removeFromSuperview()
        let replacement = scroll(guideFrame)
        try await settle()
        precondition(replacement.verticalScroller is ChannelListScroller && replacement.scrollerStyle == .overlay)
        precondition(video.scrollerStyle == .legacy)
        probe.detach()
        withExtendedLifetime(window) {}
        print("Scroll style passed: guide overlay isolation, video/sidebar preservation, legacy-style changes, and scroll-view replacement")
    }
}
