//
//  DetectionDetailTests.swift
//  VisionBoxTests
//

import Foundation
import Testing
@testable import VisionBox

@MainActor
struct DetectionDetailTests {

    /// Persisted raw values must stay stable — they live in UserDefaults.
    @Test func rawValuesAreStable() {
        #expect(DetectionDetail.generic.rawValue == "generic")
        #expect(DetectionDetail.detailed.rawValue == "detailed")
    }

    @Test func defaultsToGenericWhenNothingIsStored() throws {
        let suiteName = "VisionBoxTests.DetectionDetail.empty"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        #expect(DetectionSettings(defaults: defaults).detectionDetail == .generic)
    }

    @Test func selectionPersistsAcrossInstances() throws {
        let suiteName = "VisionBoxTests.DetectionDetail.roundTrip"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = DetectionSettings(defaults: defaults)
        settings.detectionDetail = .detailed

        // A fresh instance (like an app relaunch) sees the stored value.
        #expect(DetectionSettings(defaults: defaults).detectionDetail == .detailed)
    }

    @Test func legacyStandardValueMapsToGenericAndRepersistsAsGeneric() throws {
        // Pre-release development builds persisted "standard" for what is now
        // Generic.
        let suiteName = "VisionBoxTests.DetectionDetail.legacy"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("standard", forKey: "detectionDetail")

        let settings = DetectionSettings(defaults: defaults)
        #expect(settings.detectionDetail == .generic)

        // Selecting Generic (or anything) persists the new stable raw value.
        settings.detectionDetail = .generic
        #expect(defaults.string(forKey: "detectionDetail") == "generic")
    }

    @Test func unknownStoredValueFallsBackToGeneric() throws {
        let suiteName = "VisionBoxTests.DetectionDetail.corrupt"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("ultra-mega-detail", forKey: "detectionDetail")

        #expect(DetectionSettings(defaults: defaults).detectionDetail == .generic)
    }

    @Test func inMemoryModePersistsNothing() throws {
        let settings = DetectionSettings(previewDetail: .detailed)
        settings.detectionDetail = .generic
        #expect(settings.detectionDetail == .generic)
    }
}
