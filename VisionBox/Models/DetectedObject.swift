//
//  DetectedObject.swift
//  VisionBox
//

import CoreGraphics
import Foundation

/// A single object detected in an analyzed image.
///
/// Deliberately minimal: a name and a box. Detection Detail (Standard vs
/// Detailed) changes only how specific `label` is — there is no category or
/// other product metadata, because VisionBox is a detection showcase, not an
/// inventory app.
nonisolated struct DetectedObject: Identifiable, Equatable, Sendable {
    let id: UUID
    var label: String
    var confidence: Double?
    var boundingBox: BoundingBox

    init(
        id: UUID = UUID(),
        label: String,
        confidence: Double? = nil,
        boundingBox: BoundingBox
    ) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

extension [DetectedObject] {
    /// The object whose bounding box contains the given normalized point.
    ///
    /// When boxes overlap, the smallest box wins so that an object nested
    /// inside a larger one (a pen on a notebook) remains selectable.
    func object(at point: CGPoint) -> DetectedObject? {
        self.filter { $0.boundingBox.contains(point) }
            .min { $0.boundingBox.area < $1.boundingBox.area }
    }

    /// Rendered-space hit test with a minimum touch target: a tiny
    /// detection's *hit* area (never its drawn box) is expanded to at least
    /// `minimumTarget` points on each axis, so small objects stay tappable.
    /// Overlaps still resolve by smallest actual box area, preserving
    /// nested-object selection.
    func object(
        at point: CGPoint,
        renderedSize: CGSize,
        minimumTarget: CGFloat = 44
    ) -> DetectedObject? {
        self.filter { object in
            let rect = ImageGeometry.rect(for: object.boundingBox, in: renderedSize)
            let width = Swift.max(rect.width, minimumTarget)
            let height = Swift.max(rect.height, minimumTarget)
            let hitRect = CGRect(
                x: rect.midX - width / 2,
                y: rect.midY - height / 2,
                width: width,
                height: height
            )
            return hitRect.contains(point)
        }
        .min { $0.boundingBox.area < $1.boundingBox.area }
    }
}
