//
//  AppDependencies.swift
//  VisionBox
//

/// The app's shared services, created once in `VisionBoxApp` and passed down
/// by constructor injection. Deliberately tiny — no framework, no locator.
///
/// There are exactly two detection concepts: Demo Mode (bundled scenes, no
/// key, no network) and live Gemini analysis for personal photos.
struct AppDependencies {
    /// Observable credential state, shared by Settings (writes) and Scan
    /// (reads availability). Backed by the Keychain; previews substitute an
    /// in-memory store via the memberwise initializer.
    var geminiKeyStore = GeminiKeyStore()

    /// Demo Mode's zero-key detection service.
    var demoDetectionService: any ObjectDetectionService = DemoDetectionService()

    /// Non-sensitive detection preferences (Detection Detail), selected on
    /// the Scan screen and read at analyze time.
    var detectionSettings = DetectionSettings()

    /// One-time Scan discoverability flags (intro card, demo pill).
    var onboardingHints = OnboardingHints()

    /// A live Gemini service for the given key and detail level. Constructed
    /// fresh per analysis so a replaced key or changed preference is always
    /// the one used — no stale service. The Gemini service itself never
    /// touches the Keychain or UserDefaults.
    func liveDetectionService(apiKey: String, detail: DetectionDetail) -> any ObjectDetectionService {
        GeminiDetectionService(apiKey: apiKey, detail: detail)
    }

    /// Minimal credential/model-access validation for Settings.
    func validateAPIKey(_ key: String) async throws {
        try await GeminiDetectionService(apiKey: key).validateKey()
    }
}
