//
//  DemoScenePicker.swift
//  VisionBox
//

import SwiftUI

/// Sheet for choosing which bundled demo scene to analyze.
struct DemoScenePicker: View {
    let onSelect: (DemoScene) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(DemoScene.all) { scene in
                    Button {
                        onSelect(scene)
                    } label: {
                        DemoSceneCard(scene: scene)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Analyze the \(scene.title) demo scene")
                }
            }
            .padding()
        }
        .navigationTitle("Choose a Demo Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}

/// One demo scene option: image preview plus a short title.
private struct DemoSceneCard: View {
    let scene: DemoScene

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = scene.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(scene.detections.count) objects")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        DemoScenePicker { _ in }
    }
}
