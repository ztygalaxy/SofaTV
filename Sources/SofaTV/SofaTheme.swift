import AppKit
import SwiftUI

extension NSColor {
    // Main body colour of the television in AppIcon.svg (#3DB7AB).
    static let sofaAccent = NSColor(srgbRed: 61.0 / 255, green: 183.0 / 255, blue: 171.0 / 255, alpha: 1)

    static func sofaBackground(for appearance: NSAppearance) -> NSColor {
        let mode = appearance.bestMatch(from: [.darkAqua, .aqua])
        return mode == .darkAqua
            ? NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
            : NSColor(srgbRed: 0.92, green: 0.93, blue: 0.94, alpha: 1)
    }
    static let sofaBackground = NSColor(name: "SofaTVBackground") { sofaBackground(for: $0) }
}

extension Color {
    static let sofaAccent = Color(nsColor: .sofaAccent)
    static let sofaBackground = Color(nsColor: .sofaBackground)
}
