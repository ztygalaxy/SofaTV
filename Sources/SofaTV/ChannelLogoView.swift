import AppKit
import SwiftUI

struct ChannelLogoView: View {
    let channelName: String
    let isSelected: Bool

    var body: some View {
        Group {
            if let image = ChannelLogoStore.image(for: channelName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.31), radius: 0.7, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.18), radius: 1.4, x: 0, y: 0.8)
            } else if let image = ChannelLogoStore.fallbackImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "tv")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .frame(width: 58, height: 36)
        .accessibilityHidden(true)
    }
}

@MainActor enum ChannelLogoStore {
    private static var images: [String: NSImage] = [:]
    private static var resolvedResources: [String: String] = [:]
    private static var missingChannels: Set<String> = []
    private static let availableResources: Set<String> = {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("ChannelLogos"),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return Set(files.filter { $0.pathExtension.lowercased() == "png" }.map { $0.deletingPathExtension().lastPathComponent })
    }()
    static let fallbackImage = Bundle.main.url(forResource: "Television", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    static func image(for channelName: String) -> NSImage? {
        if missingChannels.contains(channelName) { return nil }
        let resourceName: String
        if let resolved = resolvedResources[channelName] {
            resourceName = resolved
        } else if let resolved = ChannelLogoResolver.resourceName(for: channelName, availableResources: availableResources) {
            resolvedResources[channelName] = resolved
            resourceName = resolved
        } else {
            missingChannels.insert(channelName)
            return nil
        }
        if let cached = images[resourceName] { return cached }
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: "ChannelLogos"
        ), let image = NSImage(contentsOf: url) else { return nil }
        images[resourceName] = image
        return image
    }
}
