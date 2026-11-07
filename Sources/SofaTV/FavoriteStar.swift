import SwiftUI

struct FavoriteStar: View {
    let isFavorite: Bool
    var contentScale: CGFloat = 1

    private static let side: CGFloat = 19
    private static let outline = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
    private static let trailingCorrection: CGFloat = {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        return rect.maxX - RoundedStar().path(in: rect).strokedPath(outline).boundingRect.maxX
    }()

    var body: some View {
        RoundedStar()
            .fill(isFavorite ? Color.primary : Color.clear)
            .overlay { RoundedStar().stroke(style: StrokeStyle(lineWidth: 1.5 * contentScale, lineCap: .round, lineJoin: .round)) }
            .frame(width: Self.side * contentScale, height: Self.side * contentScale)
            // Keep the visible edge aligned without a state-dependent layout guide.
            .offset(x: Self.trailingCorrection * contentScale)
    }
}

/// Curve both the outer tips and inner corners so the outline stays soft at small sizes.
private struct RoundedStar: Shape {
    func path(in rect: CGRect) -> Path {
        let side = max(0, min(rect.width, rect.height) - 2)
        let points = (0..<10).map { index in
            let angle = Double(index) * .pi / 5 - .pi / 2
            let radius = side * (index.isMultiple(of: 2) ? 0.5 : 0.24)
            return CGPoint(x: rect.midX + CGFloat(cos(angle)) * radius,
                           y: rect.midY + CGFloat(sin(angle)) * radius)
        }
        func near(_ corner: CGPoint, toward neighbor: CGPoint) -> CGPoint {
            CGPoint(x: corner.x + (neighbor.x - corner.x) * 0.20,
                    y: corner.y + (neighbor.y - corner.y) * 0.20)
        }
        var path = Path()
        path.move(to: near(points[0], toward: points[9]))
        for index in points.indices {
            let next = (index + 1) % points.count
            path.addQuadCurve(to: near(points[index], toward: points[next]), control: points[index])
            path.addLine(to: near(points[next], toward: points[index]))
        }
        path.closeSubpath()
        return path
    }
}
