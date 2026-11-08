import AppKit
import Foundation

@main
struct RenderReadmeImages {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let output = root.appendingPathComponent("docs/images", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        // Use the build output so README previews match the packaged Dock icon.
        // Run scripts/build-icon.swift (or scripts/build-app.sh) before this renderer.
        guard let baseIcon = NSImage(contentsOf: root.appendingPathComponent(".build/AppIcon.icns")),
              let channelLogo = NSImage(contentsOf: root.appendingPathComponent("Assets/ChannelLogos/浙江卫视.png")) else {
            throw NSError(domain: "SofaTV.ReadmeImages", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing built AppIcon.icns or channel logo; run scripts/build-icon.swift first"])
        }

        baseIcon.size = NSSize(width: 512, height: 512)
        let playingView = DockIconBadgeView(
            frame: NSRect(x: 0, y: 0, width: 512, height: 512),
            baseImage: baseIcon,
            badgeImage: channelLogo
        )
        guard let playingRep = playingView.bitmapImageRepForCachingDisplay(in: playingView.bounds) else {
            throw NSError(domain: "SofaTV.ReadmeImages", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not render Dock icon"])
        }
        playingView.cacheDisplay(in: playingView.bounds, to: playingRep)
        let playingIcon = NSImage(size: playingView.bounds.size)
        playingIcon.addRepresentation(playingRep)

        try writePreview(icon: baseIcon, to: output.appendingPathComponent("dock-idle.png"))
        try writePreview(icon: playingIcon, to: output.appendingPathComponent("dock-playing.png"))
    }

    @MainActor
    private static func writePreview(icon: NSImage, to url: URL) throws {
        let side = 640
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "SofaTV.ReadmeImages", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not allocate preview bitmap"])
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
        icon.draw(in: NSRect(x: 32, y: 32, width: 576, height: 576), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SofaTV.ReadmeImages", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not encode preview PNG"])
        }
        try data.write(to: url, options: .atomic)
    }
}
