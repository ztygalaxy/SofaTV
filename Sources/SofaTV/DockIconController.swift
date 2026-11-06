import AppKit

@MainActor
final class DockIconController {
    static let shared = DockIconController()

    private var baseIcon: NSImage?

    func configure(baseIcon: NSImage) {
        self.baseIcon = baseIcon
    }

    func show(channelName: String) {
        guard let baseIcon = baseIcon ?? NSApp.applicationIconImage,
              let badge = ChannelLogoStore.image(for: channelName) ?? ChannelLogoStore.fallbackImage else {
            reset()
            return
        }
        let tile = NSApp.dockTile
        let size = tile.size.width > 0 && tile.size.height > 0 ? tile.size : NSSize(width: 128, height: 128)
        tile.contentView = DockIconBadgeView(
            frame: NSRect(origin: .zero, size: size),
            baseImage: baseIcon,
            badgeImage: badge
        )
        tile.display()
    }

    func reset() {
        let tile = NSApp.dockTile
        tile.contentView = nil
        if let baseIcon { NSApp.applicationIconImage = baseIcon }
        tile.display()
    }
}
