import SwiftUI

/// Draws a deck's punch-hole silhouette in its frame. All outlines are defined in a unit square
/// (y down) and scaled, so the same numbers drive the HTML theme demo in `docs/design/themes/`.
public struct PunchHoleShape: Shape {
    public let kind: WXDeck.PunchShape

    public init(_ kind: WXDeck.PunchShape) {
        self.kind = kind
    }

    public func path(in rect: CGRect) -> Path {
        let unit = Self.unitPath(kind)
        return unit.applying(CGAffineTransform(a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY))
    }

    static func unitPath(_ kind: WXDeck.PunchShape) -> Path {
        switch kind {
        case .circle:
            return Path(ellipseIn: CGRect(x: 0, y: 0, width: 1, height: 1))
        case .star:
            return polygon(starPoints(count: 5, inner: 0.42, center: CGPoint(x: 0.5, y: 0.54), radius: 0.5))
        case .drop:
            // Point at the top, round belly below (two straight-ish shoulders + a half circle).
            let k: CGFloat = 0.5523 * 0.36
            var path = Path()
            path.move(to: CGPoint(x: 0.5, y: 0))
            path.addCurve(to: CGPoint(x: 0.86, y: 0.64), control1: CGPoint(x: 0.5, y: 0), control2: CGPoint(x: 0.86, y: 0.42))
            path.addCurve(to: CGPoint(x: 0.5, y: 1), control1: CGPoint(x: 0.86, y: 0.64 + k), control2: CGPoint(x: 0.5 + k, y: 1))
            path.addCurve(to: CGPoint(x: 0.14, y: 0.64), control1: CGPoint(x: 0.5 - k, y: 1), control2: CGPoint(x: 0.14, y: 0.64 + k))
            path.addCurve(to: CGPoint(x: 0.5, y: 0), control1: CGPoint(x: 0.14, y: 0.42), control2: CGPoint(x: 0.5, y: 0))
            path.closeSubpath()
            return path
        case .keyhole:
            let head = Path(ellipseIn: CGRect(x: 0.2, y: 0, width: 0.6, height: 0.6))
            let foot = polygon([CGPoint(x: 0.4, y: 0.45), CGPoint(x: 0.6, y: 0.45), CGPoint(x: 0.72, y: 1), CGPoint(x: 0.28, y: 1)])
            return head.union(foot)
        case .flower:
            let r: CGFloat = 0.26
            let centres = [CGPoint(x: 0.5, y: 0.26), CGPoint(x: 0.74, y: 0.5), CGPoint(x: 0.5, y: 0.74), CGPoint(x: 0.26, y: 0.5)]
            var shape = Path(ellipseIn: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
            for centre in centres {
                shape = shape.union(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)))
            }
            return shape
        case .pixel:
            return polygon([
                CGPoint(x: 0.2, y: 0), CGPoint(x: 0.8, y: 0), CGPoint(x: 0.8, y: 0.2), CGPoint(x: 1, y: 0.2),
                CGPoint(x: 1, y: 0.8), CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.8, y: 1), CGPoint(x: 0.2, y: 1),
                CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0, y: 0.8), CGPoint(x: 0, y: 0.2), CGPoint(x: 0.2, y: 0.2),
            ])
        case .sparkle:
            var path = Path()
            path.move(to: CGPoint(x: 0.5, y: 0))
            path.addQuadCurve(to: CGPoint(x: 1, y: 0.5), control: CGPoint(x: 0.56, y: 0.44))
            path.addQuadCurve(to: CGPoint(x: 0.5, y: 1), control: CGPoint(x: 0.56, y: 0.56))
            path.addQuadCurve(to: CGPoint(x: 0, y: 0.5), control: CGPoint(x: 0.44, y: 0.56))
            path.addQuadCurve(to: CGPoint(x: 0.5, y: 0), control: CGPoint(x: 0.44, y: 0.44))
            path.closeSubpath()
            return path
        case .diamond:
            return polygon([CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 0.5)])
        case .moon:
            let disc = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1, height: 1))
            let bite = Path(ellipseIn: CGRect(x: 0.3, y: -0.06, width: 0.84, height: 0.84))
            return disc.subtracting(bite)
        case .heart:
            let left = Path(ellipseIn: CGRect(x: 0.02, y: 0.08, width: 0.54, height: 0.54))
            let right = Path(ellipseIn: CGRect(x: 0.44, y: 0.08, width: 0.54, height: 0.54))
            let point = polygon([CGPoint(x: 0.06, y: 0.48), CGPoint(x: 0.5, y: 0.3), CGPoint(x: 0.94, y: 0.48), CGPoint(x: 0.5, y: 0.96)])
            return left.union(right).union(point)
        }
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    /// Points of a regular star, starting straight up.
    static func starPoints(count: Int, inner: CGFloat, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0..<(count * 2)).map { index in
            let angle = -Double.pi / 2 + Double(index) * Double.pi / Double(count)
            let length = index.isMultiple(of: 2) ? radius : radius * inner
            return CGPoint(x: center.x + length * cos(angle), y: center.y + length * sin(angle))
        }
    }
}

#Preview("Punch shapes") {
    HStack(spacing: 12) {
        ForEach(WXDeck.PunchShape.allCases, id: \.self) { kind in
            PunchHoleShape(kind).fill(Color(wxHex: 0xF7F3EA)).frame(width: 18, height: 18)
        }
    }
    .padding()
    .background(Color(wxHex: 0x3D405B))
}
