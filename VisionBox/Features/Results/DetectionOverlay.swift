//
//  DetectionOverlay.swift
//  VisionBox
//

import SwiftUI

/// Draws bounding boxes over an analyzed image and handles tap selection.
///
/// Designed to be attached with `.overlay { }` to a `.resizable().scaledToFit()`
/// image: SwiftUI then sizes this view to exactly the rendered image bounds,
/// so `GeometryReader` reports the displayed image size and normalized-to-view
/// conversion is a pure multiply, recomputed on every layout pass. Boxes stay
/// aligned through rotation, window resizing, and fold/unfold with no cached
/// geometry and no screen-size math.
struct DetectionOverlay: View {
    let objects: [DetectedObject]
    @Binding var selectedObjectID: UUID?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(objects.enumerated()), id: \.element.id) { index, object in
                    boundingBox(for: object, number: index + 1, in: geometry.size)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                select(at: location, in: geometry.size)
            }
        }
    }

    private func boundingBox(for object: DetectedObject, number: Int, in size: CGSize) -> some View {
        let rect = ImageGeometry.rect(for: object.boundingBox, in: size)
        let isSelected = object.id == selectedObjectID
        let color: Color = isSelected ? .accentColor : .yellow

        return RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? color.opacity(0.15) : .clear)
            .stroke(color, lineWidth: isSelected ? 3 : 1.5)
            .overlay(alignment: .topLeading) {
                // The number badge sits inside the box, so it can never be
                // clipped outside the image for boxes near an edge.
                Text("\(number)")
                    .font(.caption2.bold())
                    .foregroundStyle(.black)
                    .frame(width: 18, height: 18)
                    .background(color, in: .circle)
                    .padding(3)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    /// A single tap gesture for the whole overlay: the tap point is converted
    /// to normalized coordinates and hit-tested against the detections, with
    /// the smallest containing box winning. Tapping empty space deselects.
    private func select(at location: CGPoint, in size: CGSize) {
        let normalizedPoint = ImageGeometry.normalizedPoint(location, in: size)
        withAnimation {
            selectedObjectID = objects.object(at: normalizedPoint)?.id
        }
    }
}

#Preview {
    @Previewable @State var selectedObjectID: UUID? = SampleDetections.objects[0].id

    Image(uiImage: SampleDetections.image)
        .resizable()
        .scaledToFit()
        .overlay {
            DetectionOverlay(
                objects: SampleDetections.objects,
                selectedObjectID: $selectedObjectID
            )
        }
        .padding()
}
