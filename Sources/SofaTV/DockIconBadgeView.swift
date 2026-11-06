import AppKit

final class DockIconBadgeView: NSView {
    let baseImage: NSImage
    let badgeImage: NSImage
    let badgeSourceRect: NSRect

    init(frame: NSRect, baseImage: NSImage, badgeImage: NSImage) {
        self.baseImage = baseImage
        self.badgeImage = badgeImage
        self.badgeSourceRect = Self.visibleContentRect(in: badgeImage)
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.imageInterpolation = .high
        baseImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)

        let unit = min(bounds.width, bounds.height)
        let logoRect = badgeRect(for: badgeSourceRect.size)
        NSGraphicsContext.saveGraphicsState()
        let logoShadow = NSShadow()
        logoShadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        logoShadow.shadowBlurRadius = unit * 0.014
        logoShadow.shadowOffset = NSSize(width: 0, height: -unit * 0.005)
        logoShadow.set()
        badgeImage.draw(in: logoRect, from: badgeSourceRect, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func visibleContentRect(in image: NSImage) -> NSRect {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0 else {
            return NSRect(origin: .zero, size: image.size)
        }
        var minX = bitmap.pixelsWide
        var minY = bitmap.pixelsHigh
        var maxX = -1
        var maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return NSRect(origin: .zero, size: image.size) }
        let scaleX = image.size.width / CGFloat(bitmap.pixelsWide)
        let scaleY = image.size.height / CGFloat(bitmap.pixelsHigh)
        return NSRect(
            x: CGFloat(minX) * scaleX,
            y: CGFloat(minY) * scaleY,
            width: CGFloat(maxX - minX + 1) * scaleX,
            height: CGFloat(maxY - minY + 1) * scaleY
        )
    }

    func badgeRect(for imageSize: NSSize) -> NSRect {
        let unit = min(bounds.width, bounds.height)
        guard imageSize.width > 0, imageSize.height > 0, unit > 0 else { return .zero }
        let width = unit * 2 / 3
        let height = width / (imageSize.width / imageSize.height)
        return NSRect(
            x: bounds.maxX - unit * 0.02 - width,
            y: bounds.maxY - unit * 0.02 - height,
            width: width,
            height: height
        )
    }
}
