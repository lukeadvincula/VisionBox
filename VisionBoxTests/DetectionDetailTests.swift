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
        #expect(DetectionDetail.standard.rawValue == "standard")
        #expect(DetectionDetail.detailed.rawValue == "detailed")
    }

    @Test func defaultsToStandardWhenNothingIsStored() throws {
        let suiteName = "VisionBoxTests.DetectionDetail.empty"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        #expect(DetectionSettings(defaults: defaults).detectionDetail == .standard)
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

    @Test func unknownStoredValueFallsBackToStandard() throws {
        let suiteName = "VisionBoxTests.DetectionDetail.corrupt"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("ultra-mega-detail", forKey: "detectionDetail")

        #expect(DetectionSettings(defaults: defaults).detectionDetail == .standard)
    }

    @Test func inMemoryModePersistsNothing() throws {
        let settings = DetectionSettings(previewDetail: .detailed)
        settings.detectionDetail = .standard
        // Nothing to assert against defaults — this simply must not crash and
        // must keep the value in memory.
        #expect(settings.detectionDetail == .standard)
    }
}
