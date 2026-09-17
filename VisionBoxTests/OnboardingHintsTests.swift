//
//  OnboardingHintsTests.swift
//  VisionBoxTests
//

import Foundation
import Testing
@testable import VisionBox

@MainActor
struct OnboardingHintsTests {

    @Test func hintsDefaultToNotShown() throws {
        let suiteName = "VisionBoxTests.OnboardingHints.empty"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let hints = OnboardingHints(defaults: defaults)
        #expect(!hints.hasShownScanHint)
        #expect(!hints.hasShownDemoModeHint)
    }

    @Test func scanHintPersistsAcrossInstancesButDemoHintDoesNot() throws {
        let suiteName = "VisionBoxTests.OnboardingHints.persist"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let hints = OnboardingHints(defaults: defaults)
        hints.markScanHintShown()
        hints.markDemoHintShown()
        #expect(hints.hasShownDemoModeHint)

        // A fresh instance (like an app relaunch) sees the intro-card flag,
        // but the demo pill is once-per-run: it resets on every launch.
        let relaunched = OnboardingHints(defaults: defaults)
        #expect(relaunched.hasShownScanHint)
        #expect(!relaunched.hasShownDemoModeHint)
    }

    @Test func inMemoryModeStartsFromInjectedStateAndPersistsNothing() {
        let hints = OnboardingHints(previewScanHintShown: true, demoHintShown: false)
        #expect(hints.hasShownScanHint)
        #expect(!hints.hasShownDemoModeHint)

        hints.markDemoHintShown()
        #expect(hints.hasShownDemoModeHint)
    }
}
