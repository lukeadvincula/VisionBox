//
//  BoundingBox.swift
//  VisionBox
//

import CoreGraphics

/// A detection bounding box in normalized image coordinates.
///
/// All values are fractions of the image size (0.0...1.0) with the origin at
/// the image's top-left corner, so the box is independent of how large the
/// image is rendered on screen.
nonisolated struct BoundingBox: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var area: Double { width * height }

    /// The intersection of this box with the unit rectangle.
    /// Degenerate boxes (negative size, or entirely outside) collapse to zero size.
    func clamped() -> BoundingBox {
        let minX = min(max(x, 0), 1)
        let minY = min(max(y, 0), 1)
        let maxX = min(max(x + width, minX), 1)
        let maxY = min(max(y + height, minY), 1)
        return BoundingBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether a normalized point lies inside the box. Edges are inclusive.
    func contains(_ point: CGPoint) -> Bool {
        point.x >= x && point.x <= x + width &&
        point.y >= y && point.y <= y + height
    }
}
