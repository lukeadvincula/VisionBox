//
//  DemoDetectionService.swift
//  VisionBox
//

import Foundation

/// Demo Mode's implementation of the detection seam: no network, no API key.
///
/// Recognizes the bundled demo images by their exact bytes and returns that
/// scene's hand-authored detections after a short artificial delay, so the
/// analyzing state is visible and the flow matches what live Gemini analysis
/// will feel like. The delay cooperates with task cancellation.
nonisolated struct DemoDetectionService: ObjectDetectionService {

    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        try await Task.sleep(for: .milliseconds(800))
        guard let scene = DemoScene.all.first(where: { $0.imageData == imageData }) else {
            throw DemoDetectionError.unrecognizedImage
        }
        return scene.detections
    }
}

/// Demo Mode only understands its own bundled images.
nonisolated enum DemoDetectionError: Error {
    case unrecognizedImage
}
