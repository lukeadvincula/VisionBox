//
//  ImageGeometry.swift
//  VisionBox
//

import CoreGraphics

/// Conversions between normalized image coordinates and rendered view coordinates.
///
/// The container size is expected to be the *rendered* size of the displayed
/// image (see `DetectionOverlay`), never screen or device dimensions.
nonisolated enum ImageGeometry {

    /// Maps a normalized bounding box into a container's coordinate space.
    /// The box is clamped to the unit rectangle first, so out-of-range
    /// detections never draw outside the image.
    static func rect(for box: BoundingBox, in containerSize: CGSize) -> CGRect {
        let box = box.clamped()
        return CGRect(
            x: box.x * containerSize.width,
            y: box.y * containerSize.height,
            width: box.width * containerSize.width,
            height: box.height * containerSize.height
        )
    }

    /// Maps a point in a container's coordinate space to normalized image
    /// coordinates, clamped to the unit rectangle. A zero-sized container
    /// maps to the origin rather than producing NaN.
    static func normalizedPoint(_ point: CGPoint, in containerSize: CGSize) -> CGPoint {
        guard containerSize.width > 0, containerSize.height > 0 else { return .zero }
        return CGPoint(
            x: min(max(point.x / containerSize.width, 0), 1),
            y: min(max(point.y / containerSize.height, 0), 1)
        )
    }
}
