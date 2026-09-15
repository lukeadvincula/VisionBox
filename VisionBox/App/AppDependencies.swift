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
    let keychain = KeychainService()

    /// Demo Mode's zero-key detection service.
    let demoDetectionService: any ObjectDetectionService = DemoDetectionService()

    /// The live Gemini service, available only while an API key is stored.
    /// Resolved at analyze time so key changes take effect immediately. The
    /// key is read here and injected — the Gemini service itself never
    /// touches the Keychain.
    func liveDetectionService() -> (any ObjectDetectionService)? {
        guard let apiKey = try? keychain.readAPIKey(), !apiKey.isEmpty else {
            return nil
        }
        return GeminiDetectionService(apiKey: apiKey)
    }
}
