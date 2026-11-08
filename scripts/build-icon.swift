import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fatalError("Usage: build-icon.swift artwork.svg output.iconset television.png app.icns")
}
let input = URL(fileURLWithPath: arguments[1])
let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
let iconURL = URL(fileURLWithPath: arguments[4])
guard let image = NSImage(contentsOf: input) else { fatalError("Cannot render AppIcon.svg") }

try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var iconRepresentations: [(type: String, data: Data)] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Cannot allocate icon bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        let side = CGFloat(pixels)
        NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))
        // Keep the standard Dock footprint; the shared SVG contains only the television.
        let tileMargin = side * 0.10
        let tile = NSRect(x: tileMargin, y: tileMargin, width: side * 0.80, height: side * 0.80)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: side * 0.18, yRadius: side * 0.18)
        let tileTop = NSColor.white
        let tileBottom = NSColor(srgbRed: 250.0 / 255, green: 250.0 / 255, blue: 252.0 / 255, alpha: 1)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
        shadow.shadowBlurRadius = side * 0.012
        shadow.shadowOffset = NSSize(width: 0, height: -side * 0.006)
        shadow.set()
        tileBottom.setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: tileTop, ending: tileBottom)?.draw(in: tilePath, angle: -90)
        image.draw(in: NSRect(x: side * 0.19, y: side * 0.20, width: side * 0.62, height: side * 0.62))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        let type: String
        switch (size, scale) {
        case (16, 1): type = "icp4"
        case (16, 2): type = "ic11"
        case (32, 1): type = "icp5"
        case (32, 2): type = "ic12"
        case (128, 1): type = "ic07"
        case (128, 2): type = "ic13"
        case (256, 1): type = "ic08"
        case (256, 2): type = "ic14"
        case (512, 1): type = "ic09"
        case (512, 2): type = "ic10"
        default: fatalError("Unsupported icon representation")
        }
        iconRepresentations.append((type, png))
    }
}

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var encoded = value.bigEndian
    withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
}

var icns = Data("icns".utf8)
let iconLength = 8 + iconRepresentations.reduce(0) { $0 + 8 + $1.data.count }
appendBigEndian(UInt32(iconLength), to: &icns)
for representation in iconRepresentations {
    icns.append(Data(representation.type.utf8))
    appendBigEndian(UInt32(8 + representation.data.count), to: &icns)
    icns.append(representation.data)
}
try icns.write(to: iconURL, options: .atomic)

// The empty player uses the same centered-antenna artwork without the Dock tile.
let previewURL = URL(fileURLWithPath: arguments[3])
guard let preview = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Cannot allocate television bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
NSGraphicsContext.current?.imageInterpolation = .high
NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: 512, height: 512))
image.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
NSGraphicsContext.restoreGraphicsState()
guard let previewPNG = preview.representation(using: .png, properties: [:]) else { fatalError("Cannot encode television artwork") }
try previewPNG.write(to: previewURL)
