//
//  DetectedObject.swift
//  VisionBox
//

import Foundation

/// A single object detected in an analyzed image.
nonisolated struct DetectedObject: Identifiable, Equatable, Sendable {
    let id: UUID
    var label: String
    var category: String?
    var confidence: Double?
    var boundingBox: BoundingBox

    init(
        id: UUID = UUID(),
        label: String,
        category: String? = nil,
        confidence: Double? = nil,
        boundingBox: BoundingBox
    ) {
        self.id = id
        self.label = label
        self.category = category
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
}
