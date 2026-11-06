import AppKit

@main struct DockIconBadgeChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let base = solidImage(size: NSSize(width: 256, height: 256), color: .systemTeal)
        let badge = solidImage(size: NSSize(width: 160, height: 60), color: .systemRed)
        let view = DockIconBadgeView(
            frame: NSRect(x: 0, y: 0, width: 256, height: 256),
            baseImage: base,
            badgeImage: badge
        )
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            preconditionFailure("Could not allocate Dock icon bitmap")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let badgeCenter = bitmap.colorAt(x: 204, y: 47)?.usingColorSpace(.sRGB)
        let flippedBadgeCenter = bitmap.colorAt(x: 204, y: 208)?.usingColorSpace(.sRGB)
        let baseCenter = bitmap.colorAt(x: 128, y: 150)?.usingColorSpace(.sRGB)
        let badgeRect = view.badgeRect(for: badge.size)
        precondition(
            max(badgeCenter?.redComponent ?? 0, flippedBadgeCenter?.redComponent ?? 0) > 0.7,
            "Channel badge is not visible at bottom-right"
        )
        precondition((baseCenter?.greenComponent ?? 0) > 0.35, "Base application icon was not preserved")
        precondition(abs(badgeRect.width - 256 * 2 / 3) < 0.01, "Channel badge width should be two thirds of the Dock icon")
        precondition(abs(badgeRect.width / badgeRect.height - badge.size.width / badge.size.height) < 0.01, "Channel badge width should preserve its aspect ratio")
        precondition(abs(badgeRect.maxX - 256 * 0.98) < 0.01, "Channel badge should extend beyond the app artwork on the right")
        precondition(abs(badgeRect.maxY - 256 * 0.98) < 0.01, "Channel badge should extend beyond the app artwork at the top")
        precondition(view.baseImage === base && view.badgeImage === badge)

        let paddedBadge = paddedImage(
            size: NSSize(width: 300, height: 180),
            visibleRect: NSRect(x: 18, y: 45, width: 267, height: 95),
            color: .systemRed
        )
        let paddedView = DockIconBadgeView(frame: view.frame, baseImage: base, badgeImage: paddedBadge)
        precondition(abs(paddedView.badgeSourceRect.width - 267) < 1, "Transparent horizontal padding should be trimmed")
        precondition(abs(paddedView.badgeSourceRect.height - 95) < 1, "Transparent vertical padding should be trimmed")
        let normalizedRect = paddedView.badgeRect(for: paddedView.badgeSourceRect.size)
        precondition(abs(normalizedRect.width - 256 * 2 / 3) < 0.01, "Visible logo content should use the standard rendered width")
        print("Dock icon base artwork and top-right channel badge rendering passed")
    }

    private static func solidImage(size: NSSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    private static func paddedImage(size: NSSize, visibleRect: NSRect, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: visibleRect).fill()
        image.unlockFocus()
        return image
    }
}
