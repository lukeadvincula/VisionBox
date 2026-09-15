//
//  ScanViewModel.swift
//  VisionBox
//

import UIKit
import Observation

/// Drives the scan flow: pick an image, analyze it, show results.
///
/// Image acquisition (Photos/camera) and real detection arrive in later
/// phases; for now the flow runs against the bundled sample image.
@MainActor @Observable
final class ScanViewModel {

    enum State {
        case idle
        case analyzing
        case results(image: UIImage, objects: [DetectedObject])
        case error(String)
    }

    private(set) var state: State = .idle
    private let detectionService: any ObjectDetectionService

    init(detectionService: any ObjectDetectionService) {
        self.detectionService = detectionService
    }

    /// Runs the detection flow against the bundled sample image so the
    /// Results experience can be exercised before image input exists.
    func analyzeSampleImage() async {
        let image = SampleDetections.image
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            state = .error("Couldn't prepare the sample image.")
            return
        }

        state = .analyzing
        do {
            let objects = try await detectionService.detectObjects(in: imageData)
            state = .results(image: image, objects: objects)
        } catch {
            state = .error("Analysis failed. Please try again.")
        }
    }

    func reset() {
        state = .idle
    }
}
