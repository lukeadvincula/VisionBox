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
        // The detected-object list is the accessible selection surface with
        // the same information and actions; exposing every box here as well
        // would give VoiceOver users each detection twice. The annotated
        // image itself carries a summary label (see ResultsView).
        .accessibilityHidden(true)
    }

    private func boundingBox(for object: DetectedObject, number: Int, in size: CGSize) -> some View {
        let rect = ImageGeometry.rect(for: object.boundingBox, in: size)
        let isSelected = object.id == selectedObjectID
        let color: Color = isSelected ? .accentColor : .yellow
        let shape = RoundedRectangle(cornerRadius: 4)

        return Group {
            if isSelected {
                // A white halo under the accent stroke (plus a soft shadow)
                // keeps the selected box unmistakable on light and dark image
                // content alike — selection never relies on hue alone.
                shape
                    .fill(color.opacity(0.15))
                    .stroke(.white.opacity(0.9), lineWidth: 5.5)
                    .stroke(color, lineWidth: 3)
                    .shadow(color: .black.opacity(0.35), radius: 2)
            } else {
                shape.stroke(color, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .topLeading) {
            // The number badge sits inside the box, so it can never be
            // clipped outside the image for boxes near an edge.
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundStyle(.black)
                .frame(minWidth: 18, minHeight: 18)
                .background(color, in: .circle)
                .padding(3)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    /// A single tap gesture for the whole overlay, hit-tested in rendered
    /// coordinates with a minimum touch target so tiny detections stay
    /// tappable; the smallest containing box wins overlaps. Tapping empty
    /// space deselects.
    private func select(at location: CGPoint, in size: CGSize) {
        withAnimation {
            selectedObjectID = objects.object(at: location, renderedSize: size)?.id
        }
    }
}

#Preview {
    @Previewable @State var selectedObjectID: UUID? = DemoScene.desk.detections[0].id

    Image(uiImage: DemoScene.desk.image ?? UIImage())
        .resizable()
        .scaledToFit()
        .overlay {
            DetectionOverlay(
                objects: DemoScene.desk.detections,
                selectedObjectID: $selectedObjectID
            )
        }
        .padding()
}
