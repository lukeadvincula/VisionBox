//
//  ResultsView.swift
//  VisionBox
//

import SwiftUI

/// Shows the analyzed image with its bounding boxes alongside the detected
/// object list, arranging the two vertically or side by side based on the
/// width actually available to this view — not device model, orientation,
/// or screen bounds — so it adapts naturally to foldables and live resizing.
struct ResultsView: View {
    let image: UIImage
    let objects: [DetectedObject]

    /// Single source of truth for selection, shared by the overlay and the
    /// list. It lives outside layout state, so it survives layout changes.
    @State private var selectedObjectID: UUID?
    @State private var containerSize: CGSize

    /// Minimum available width at which the side-by-side arrangement is used.
    private static let wideLayoutMinimumWidth: CGFloat = 600

    init(image: UIImage, objects: [DetectedObject], selectedObjectID: UUID? = nil) {
        self.image = image
        self.objects = objects
        self.selectedObjectID = selectedObjectID
        self.containerSize = .zero
    }

    private var isWideLayout: Bool {
        containerSize.width >= Self.wideLayoutMinimumWidth
    }

    var body: some View {
        // AnyLayout preserves child identity across the narrow/wide switch,
        // so selection and list scroll position survive fold/unfold.
        let layout = isWideLayout
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))

        layout {
            annotatedImage
            if objects.isEmpty {
                emptyState
            } else {
                objectList
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            containerSize = size
        }
    }

    private var annotatedImage: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                // The overlay is sized to the fitted image, so box math inside
                // it maps directly to rendered image coordinates.
                DetectionOverlay(objects: objects, selectedObjectID: $selectedObjectID)
            }
            .frame(maxHeight: narrowImageMaxHeight)
            .padding()
    }

    /// In the narrow (vertical) arrangement, tall portrait images are capped
    /// to a fraction of the container's own height so the list stays usable.
    /// The image still fits entirely (`scaledToFit`) — never cropped — and the
    /// cap derives from this view's available space, never from the device.
    private var narrowImageMaxHeight: CGFloat? {
        guard !isWideLayout, containerSize.height > 0 else { return nil }
        return containerSize.height * 0.55
    }

    /// Zero detections is a normal outcome, not an error.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Objects Detected", systemImage: "magnifyingglass")
        } description: {
            Text("Nothing was detected in this image. Try a different photo or demo scene.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var objectList: some View {
        ScrollViewReader { proxy in
            List {
                Section("\(objects.count) objects detected") {
                    ForEach(Array(objects.enumerated()), id: \.element.id) { index, object in
                        DetectedObjectRow(
                            object: object,
                            number: index + 1,
                            isSelected: object.id == selectedObjectID
                        ) {
                            withAnimation {
                                selectedObjectID = selectedObjectID == object.id ? nil : object.id
                            }
                        }
                        .id(object.id)
                    }
                }
            }
            .onChange(of: selectedObjectID) { _, newValue in
                // Keep the selected row visible when selection comes from a box tap.
                if let newValue {
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }
}

/// One row in the detected object list, numbered to match its bounding box.
private struct DetectedObjectRow: View {
    let object: DetectedObject
    let number: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.background)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary), in: .circle)

                VStack(alignment: .leading) {
                    Text(object.label)
                        .foregroundStyle(.primary)
                    if let category = object.category {
                        Text(category)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let confidence = object.confidence {
                    Text(confidence.formatted(.percent.precision(.fractionLength(0))))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Previews

#Preview("Narrow") {
    NavigationStack {
        ResultsView(image: DemoScene.desk.image ?? UIImage(), objects: DemoScene.desk.detections)
    }
}

#Preview("Wide", traits: .landscapeLeft) {
    NavigationStack {
        ResultsView(image: DemoScene.desk.image ?? UIImage(), objects: DemoScene.desk.detections)
    }
}

#Preview("Selected object") {
    NavigationStack {
        ResultsView(
            image: DemoScene.desk.image ?? UIImage(),
            objects: DemoScene.desk.detections,
            selectedObjectID: DemoScene.desk.detections[2].id
        )
    }
}

#Preview("Tall image") {
    NavigationStack {
        ResultsView(image: DemoScene.kitchen.image ?? UIImage(), objects: DemoScene.kitchen.detections)
    }
}

#Preview("No detections") {
    NavigationStack {
        ResultsView(image: DemoScene.desk.image ?? UIImage(), objects: [])
    }
}
