//
//  OnboardingHints.swift
//  VisionBox
//

import Foundation
import Observation

/// Discoverability flags for the Scan screen.
///
/// The "Detect Objects" intro card shows once ever (persisted in
/// UserDefaults — never the Keychain). The expanded "Try Demo Mode" pill
/// shows once per app run: its flag is in-memory only, so every cold launch
/// reintroduces Demo Mode briefly, but returning to Scan within a run keeps
/// it collapsed. An in-memory mode exists for previews and unit tests.
@MainActor @Observable
final class OnboardingHints {

    private static let scanHintKey = "hasShownScanHint"

    private(set) var hasShownScanHint: Bool
    /// Deliberately not persisted — once per process, not once per install.
    private(set) var hasShownDemoModeHint: Bool

    /// nil in the in-memory (preview/test) mode.
    private let defaults: UserDefaults?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasShownScanHint = defaults.bool(forKey: Self.scanHintKey)
        self.hasShownDemoModeHint = false
    }

    /// In-memory hints for previews and unit tests: fixed starting state,
    /// nothing persisted.
    init(previewScanHintShown: Bool, demoHintShown: Bool) {
        self.defaults = nil
        self.hasShownScanHint = previewScanHintShown
        self.hasShownDemoModeHint = demoHintShown
    }

    func markScanHintShown() {
        hasShownScanHint = true
        defaults?.set(true, forKey: Self.scanHintKey)
    }

    func markDemoHintShown() {
        hasShownDemoModeHint = true
    }
}
