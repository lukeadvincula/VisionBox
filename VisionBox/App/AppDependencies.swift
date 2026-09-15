//
//  AppDependencies.swift
//  VisionBox
//

/// The app's shared services, created once in `VisionBoxApp` and passed down
/// by constructor injection. Deliberately tiny — no framework, no locator.
struct AppDependencies {
    /// Later phases resolve this to the Gemini or Demo Mode implementation
    /// based on the user's settings.
    let detectionService: any ObjectDetectionService

    init(detectionService: any ObjectDetectionService = SampleDetectionService()) {
        self.detectionService = detectionService
    }
}
