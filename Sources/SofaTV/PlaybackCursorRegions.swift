import AppKit

/// A background arrow must not cover sibling playback controls.
enum PlaybackCursorRegions {
    static func background(in bounds: NSRect, excluding controls: [NSRect]) -> [NSRect] {
        var regions = bounds.isEmpty ? [] : [bounds]
        for control in controls {
            regions = regions.flatMap { region -> [NSRect] in
                let cut = region.intersection(control)
                guard !cut.isEmpty else { return [region] }
                return [NSRect(x: region.minX, y: region.minY, width: cut.minX - region.minX, height: region.height),
                        NSRect(x: cut.maxX, y: region.minY, width: region.maxX - cut.maxX, height: region.height),
                        NSRect(x: cut.minX, y: region.minY, width: cut.width, height: cut.minY - region.minY),
                        NSRect(x: cut.minX, y: cut.maxY, width: cut.width, height: region.maxY - cut.maxY)]
                    .filter { !$0.isEmpty }
            }
        }
        return regions
    }
}
