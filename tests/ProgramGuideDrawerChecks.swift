import AppKit
import SwiftUI

@MainActor private final class Backdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [.systemTeal, .systemOrange, .systemIndigo])!.draw(in: bounds, angle: 0)
    }
}

@MainActor private final class OffscreenWindow: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@main struct ProgramGuideDrawerChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        var at = ISO8601DateFormatter().date(from: "2026-11-07T07:15:00Z")!
        var xml = "<tv><channel id=\"test\"><display-name>北京卫视</display-name></channel>"
        for hour in 0..<24 {
            let nextDay = hour == 23 ? "08" : "07"
            let title = hour == 15 ? "知否知否应是绿肥红瘦（52）" : "第\(hour + 1)档节目 · 电视剧场与新闻资讯"
            let startMinute = hour == 15 ? "05" : "00"
            xml += "<programme channel=\"test\" start=\"20261107\(String(format: "%02d", hour))\(startMinute)00 +0800\" stop=\"202611\(nextDay)\(String(format: "%02d", (hour + 1) % 24))0000 +0800\"><title>\(title)</title></programme>"
        }
        xml += "</tv>"
        let channel = Channel(name: "北京卫视", group: "卫视", url: URL(string: "https://example.com/live")!)
        let otherChannel = Channel(name: "江苏卫视", group: "卫视", url: URL(string: "https://example.com/other")!, epgID: "test")
        let entry = ProgramGuideCacheEntry(fetchedAt: at, guide: try ProgramGuide.parse(Data(xml.utf8)))
        let store = ProgramGuideStore(now: { at }, cachedGuide: { entry }, refreshGuide: { entry }, observeSystemEvents: false)
        store.setChannels([channel, otherChannel])
        let normal = ProgramGuidePreview(revealDelay: .zero)
        let fullscreen = ProgramGuidePreview(revealDelay: .zero)
        fullscreen.setPresentation(.fullscreen)
        let normalHost = ProgramGuideOverlayHost(preview: normal, store: store, presentation: .embedded, playingChannel: channel)
        let fullscreenHost = ProgramGuideOverlayHost(preview: fullscreen, store: store, presentation: .fullscreen, playingChannel: channel)
        normalHost.isInteractive = true; fullscreenHost.isInteractive = true
        normalHost.frame = NSRect(x: 0, y: 0, width: 260, height: 640)
        fullscreenHost.frame = NSRect(x: 280, y: 0, width: 340, height: 640)
        let window = OffscreenWindow(contentRect: NSRect(x: -10000, y: -10000, width: 620, height: 640), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        defer { window.close() }
        let content = Backdrop(frame: NSRect(x: 0, y: 0, width: 620, height: 640))
        window.contentView = content
        content.addSubview(normalHost); content.addSubview(fullscreenHost)
        window.orderBack(nil)
        normal.hover(channel, in: .embedded, inside: true)
        fullscreen.hover(channel, in: .fullscreen, inside: true)
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func settle() async throws {
            for _ in 0..<35 {
                content.layoutSubtreeIfNeeded()
                normalHost.layoutSubtreeIfNeeded(); fullscreenHost.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                for host in [normalHost, fullscreenHost] {
                    for glass in views(host).compactMap({ $0 as? NSVisualEffectView }) where glass.bounds.width > 0 {
                        precondition(abs(glass.bounds.width - host.bounds.width) < 1, "Sliding must not shrink or fold the guide")
                    }
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        func checkPosition(_ host: NSView, boundary: VerticalEdge? = nil) {
            let allScrolls = views(host).compactMap { $0 as? NSScrollView }
            precondition(allScrolls.count == 1, "Reopening must replace the old schedule")
            let scroll = allScrolls.last!
            let document = scroll.documentView!
            precondition(document.subviews.first!.frame.minY == 0 && document.subviews.last!.frame.maxY == document.bounds.maxY, "The schedule must have no extra space before its first row or after its last row")
            precondition(abs(scroll.frame.width - host.bounds.width) < 1 && abs(scroll.contentView.bounds.width - host.bounds.width) < 1, "The scroll viewport must fill the pane without a scrollbar gutter")
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsHigh) / content.bounds.height
            let markerX = content.convert(NSPoint(x: 1, y: 0), from: host).x
            let column = Int(markerX * CGFloat(bitmap.pixelsWide) / content.bounds.width)
            let playingChannel = (host as! ProgramGuideOverlayHost).playingChannel
            let accent = (playingChannel?.identity == channel.identity ? NSColor.sofaAccent : NSColor.white).usingColorSpace(.deviceRGB)!
            let markerPixels = (0..<bitmap.pixelsHigh).filter { y in
                let color = bitmap.colorAt(x: column, y: y)!.usingColorSpace(.deviceRGB)!
                return abs(color.redComponent - accent.redComponent) < 0.12 &&
                    abs(color.greenComponent - accent.greenComponent) < 0.12 &&
                    abs(color.blueComponent - accent.blueComponent) < 0.12
            }
            precondition(!markerPixels.isEmpty, "The current programme highlight must be rendered")
            let markerY = content.bounds.maxY - CGFloat(markerPixels.first! + markerPixels.last! + 1) / 2 / scale
            let viewport = content.convert(scroll.contentView.bounds, from: scroll.contentView)
            let expectedFooterHeight: CGFloat = host === normalHost ? 32 : 36 * 1.3
            precondition(abs(viewport.minY - expectedFooterHeight) < 1, "The guide footer must match the channel sidebar footer height: actual \(viewport.minY), expected \(expectedFooterHeight)")
            let distance: CGFloat
            switch boundary {
            case .top:
                let markerTop = content.bounds.maxY - CGFloat(markerPixels.first!) / scale
                distance = abs(markerTop - viewport.maxY)
                precondition(scroll.contentView.bounds.minY == 0, "The first programme must stop at the start of the list")
            case .bottom:
                let markerBottom = content.bounds.maxY - CGFloat(markerPixels.last! + 1) / scale
                distance = abs(markerBottom - viewport.minY)
                precondition(abs(scroll.contentView.bounds.maxY - document.bounds.maxY) < 1, "The last programme must stop at the end of the list")
            case nil:
                distance = abs(markerY - viewport.midY)
            }
            print("current programme position offset: \(distance) pt")
            if distance >= 3 {
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/sofatv-centering-failure.png"))
            }
            precondition(distance < 3, "Current programme position offset: \(distance), marker Y: \(markerY), viewport: \(viewport), pixel range: \(markerPixels.first!)...\(markerPixels.last!)")
            let edgeX = Int((content.convert(NSPoint(x: host.bounds.maxX - 2, y: 0), from: host).x) * scale)
            let highlightedY = (markerPixels.first! + markerPixels.last!) / 2
            let outsideY = max(0, markerPixels.first! - Int(12 * scale))
            let highlighted = bitmap.colorAt(x: edgeX, y: highlightedY)!.usingColorSpace(.deviceRGB)!
            let outside = bitmap.colorAt(x: edgeX, y: outsideY)!.usingColorSpace(.deviceRGB)!
            let edgeFill = (highlighted.redComponent + highlighted.greenComponent + highlighted.blueComponent - outside.redComponent - outside.greenComponent - outside.blueComponent) / 3
            precondition(edgeFill > 0.02, "The programme highlight must reach the pane's right edge")
        }
        try await settle()
        checkPosition(normalHost); checkPosition(fullscreenHost)

        // A gap must keep the next programme centred and visibly highlighted in
        // both presentations, then switch its label when the programme starts.
        at = ISO8601DateFormatter().date(from: "2026-11-07T07:02:00Z")!
        store.resume(); try await settle()
        precondition(store.titles[channel.id]?.hasPrefix("即将播出 · ") == true)
        checkPosition(normalHost); checkPosition(fullscreenHost)
        let upcomingPreview = CommandLine.arguments.count > 2 ? CommandLine.arguments[2]
            : ProcessInfo.processInfo.environment["SOFATV_UPCOMING_PREVIEW"]
        if let upcomingPreview {
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: upcomingPreview))
        }
        at = ISO8601DateFormatter().date(from: "2026-11-07T07:05:00Z")!
        store.resume(); try await settle()
        precondition(store.titles[channel.id]?.hasPrefix("即将播出") == false)
        checkPosition(normalHost); checkPosition(fullscreenHost)

        normal.hover(otherChannel, in: .embedded, inside: true)
        fullscreen.hover(otherChannel, in: .fullscreen, inside: true)
        try await settle()
        precondition(normal.channel == otherChannel && fullscreen.channel == otherChannel)
        normal.hoverPanel(true, in: .embedded)
        normal.hover(otherChannel, in: .embedded, inside: false)
        fullscreen.hoverPanel(true, in: .fullscreen)
        fullscreen.hover(otherChannel, in: .fullscreen, inside: false)
        normalHost.returnToCurrent(); fullscreenHost.returnToCurrent()
        precondition(normal.channel == channel && fullscreen.channel == channel, "Return must target the playing channel, not the previewed channel")
        precondition(normalHost.playingChannel == channel && fullscreenHost.playingChannel == channel, "Returning to the guide must preserve playback selection")
        try await settle()
        checkPosition(normalHost); checkPosition(fullscreenHost)
        for host in [normalHost, fullscreenHost] {
            let scroll = views(host).compactMap { $0 as? NSScrollView }.first!
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            host.returnToCurrent()
        }
        try await settle()
        checkPosition(normalHost); checkPosition(fullscreenHost)
        normal.hoverPanel(false, in: .embedded)
        normal.hover(channel, in: .embedded, inside: true)
        fullscreen.hoverPanel(false, in: .fullscreen)
        fullscreen.hover(channel, in: .fullscreen, inside: true)
        for (name, host) in [("normal", normalHost), ("fullscreen", fullscreenHost)] {
            let native = views(host)
            let scroll = native.compactMap { $0 as? NSScrollView }.first!
            print("\(name) scrolled: \(scroll.contentView.bounds.origin.y), document: \(scroll.documentView!.frame.height), viewport: \(scroll.contentView.bounds.height)")
            precondition(scroll.contentView.bounds.origin.y > 0, "\(name) must automatically scroll to the afternoon programme")
            precondition(scroll.scrollerStyle == .overlay && scroll.verticalScroller is ChannelListScroller)
            scroll.scrollerStyle = .legacy
            precondition(scroll.scrollerStyle == .overlay, "System preferences must not reserve a wide scrollbar gutter")
            let material = native.compactMap { $0 as? NSVisualEffectView }.first!
            let materialFrame = host.convert(material.bounds, from: material)
            precondition(abs(materialFrame.maxY - host.bounds.maxY) < 1, "The guide material must reach the top edge under a transparent title bar: \(materialFrame), host: \(host.bounds)")
            print("\(name) material alpha: \(material.alphaValue), text host alpha: \(host.alphaValue)")
            precondition(material.alphaValue == (name == "normal" ? 0.92 : 0.62) && host.alphaValue == 1)
            precondition(material.hitTest(NSPoint(x: 1, y: 1)) == nil, "The material must not intercept schedule controls")
        }
        // Reopening resets a manual scroll; first/last programmes stop at the natural boundaries.
        for (value, boundary) in [("2026-11-06T16:15:00Z", VerticalEdge.top), ("2026-11-07T15:15:00Z", .bottom)] {
            for host in [normalHost, fullscreenHost] {
                let scroll = views(host).compactMap { $0 as? NSScrollView }.first!
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            normal.dismiss(); fullscreen.dismiss()
            try await settle()
            at = ISO8601DateFormatter().date(from: value)!
            store.resume()
            normal.hover(channel, in: .embedded, inside: true)
            fullscreen.hover(channel, in: .fullscreen, inside: true)
            try await settle()
            checkPosition(normalHost, boundary: boundary); checkPosition(fullscreenHost, boundary: boundary)
        }
        normalHost.isInteractive = false; fullscreenHost.isInteractive = false
        precondition(normalHost.hitTest(NSPoint(x: 1, y: 1)) == nil && fullscreenHost.hitTest(NSPoint(x: 1, y: 1)) == nil)
        var removalFinished = false
        let removalStarted = Date()
        normal.dismiss {
            print("guide removal finished after \(Date().timeIntervalSince(removalStarted)) seconds")
            precondition(!views(normalHost).contains { $0 is NSVisualEffectView && !$0.isHiddenOrHasHiddenAncestor }, "The next sidebar slide must wait until the guide has slid out")
            removalFinished = true
        }
        try await settle()
        precondition(removalFinished, "Guide removal must complete before the channel sidebar can close")
        normal.hover(channel, in: .embedded, inside: true)
        try await settle()
        let activeScroll = views(normalHost).compactMap { $0 as? NSScrollView }.first!
        let beforePlayingChange = activeScroll.contentView.bounds.origin
        normalHost.playingChannel = nil
        try await settle()
        precondition(activeScroll.contentView.bounds.origin == beforePlayingChange, "Updating the current-programme label must preserve the user's scroll position")
        let revealBeforeInactiveReturn = normal.revealID
        normalHost.returnToCurrent()
        precondition(normal.revealID == revealBeforeInactiveReturn, "Without a playing channel there is no return target")
        checkPosition(normalHost, boundary: .bottom)
        checkPosition(fullscreenHost, boundary: .bottom)
        if CommandLine.arguments.count > 1 {
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        store.stop()
        withExtendedLifetime((window, normal, fullscreen)) {}
        print("Guide drawer passed: fixed-width slides, ordered removal, current programme positioning with natural list boundaries, no leading/trailing padding, edge-to-edge highlights, scroll style, and material opacity")
    }
}
