//
//  SampleDetections.swift
//  VisionBox
//

import UIKit

/// Static sample content for SwiftUI previews and pre-integration development.
///
/// The sample image is rendered in code so its shapes exactly match the
/// normalized bounding boxes below. This is not Demo Mode — real Demo Mode
/// (bundled photos with hand-authored detections) arrives in Phase 1.
enum SampleDetections {

    /// Deterministic IDs keep previews and screenshots reproducible.
    nonisolated static let objects: [DetectedObject] = [
        DetectedObject(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            label: "Coffee Mug",
            category: "Kitchenware",
            confidence: 0.94,
            boundingBox: BoundingBox(x: 0.08, y: 0.55, width: 0.22, height: 0.34)
        ),
        DetectedObject(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            label: "Notebook",
            category: "Stationery",
            confidence: 0.88,
            boundingBox: BoundingBox(x: 0.42, y: 0.45, width: 0.45, height: 0.42)
        ),
        DetectedObject(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            label: "Pen",
            category: "Stationery",
            confidence: 0.71,
            // Nested inside the notebook's box to exercise smallest-box-wins hit testing.
            boundingBox: BoundingBox(x: 0.5, y: 0.6, width: 0.25, height: 0.08)
        ),
        DetectedObject(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            label: "Potted Plant",
            category: "Decor",
            confidence: 0.82,
            boundingBox: BoundingBox(x: 0.7, y: 0.08, width: 0.22, height: 0.3)
        ),
    ]

    /// A 4:3 image whose colored shapes sit exactly where `objects` says they
    /// are, so overlaid boxes visibly align in previews and at runtime.
    static let image: UIImage = {
        let size = CGSize(width: 800, height: 600)
        let shapeColors: [UIColor] = [.systemBrown, .systemIndigo, .systemOrange, .systemTeal]

        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            for (object, color) in zip(objects, shapeColors) {
                let rect = ImageGeometry.rect(for: object.boundingBox, in: size)
                color.setFill()
                UIBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 12).fill()
            }
        }
    }()
}

/// Placeholder detection service used until the Gemini (Phase 2) and Demo Mode
/// (Phase 1) implementations exist. Ignores the input and returns the sample
/// detections after a short delay so loading states are visible.
nonisolated struct SampleDetectionService: ObjectDetectionService {
    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        try await Task.sleep(for: .milliseconds(800))
        return SampleDetections.objects
    }
}
