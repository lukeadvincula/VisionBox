//
//  ObjectDetectionService.swift
//  VisionBox
//

import Foundation

/// The seam between the UI and whatever performs object detection.
///
/// Later phases provide a Gemini-backed implementation and a Demo Mode
/// implementation; unit tests can substitute simple stubs.
nonisolated protocol ObjectDetectionService: Sendable {
    /// Analyzes prepared image data and returns the objects detected in it.
    func detectObjects(in imageData: Data) async throws -> [DetectedObject]
}
