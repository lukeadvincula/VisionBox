//
//  AppDependencies.swift
//  VisionBox
//

/// The app's shared services, created once in `VisionBoxApp` and passed down
/// by constructor injection. Deliberately tiny — no framework, no locator.
struct AppDependencies {
    /// The service behind the analyze flow. Demo Mode ships first; the
    /// Gemini-backed service for personal photos arrives in the next phase.
    let detectionService: any ObjectDetectionService

    init(detectionService: any ObjectDetectionService = DemoDetectionService()) {
        self.detectionService = detectionService
    }
}
