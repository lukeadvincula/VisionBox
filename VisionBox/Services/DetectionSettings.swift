//
//  DetectionSettings.swift
//  VisionBox
//

import Foundation
import Observation

/// The user's detection preferences — ordinary, non-sensitive settings.
///
/// Backed by UserDefaults (the Keychain remains exclusively for the Gemini
/// API key). Observable and shared via `AppDependencies`, so a change in
/// Settings applies to the next analysis immediately, no restart.
@MainActor @Observable
final class DetectionSettings {

    private static let detailKey = "detectionDetail"

    var detectionDetail: DetectionDetail {
        didSet {
            defaults?.set(detectionDetail.rawValue, forKey: Self.detailKey)
        }
    }

    /// nil in the in-memory (preview/test) mode.
    private let defaults: UserDefaults?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Absent, unknown, or corrupt stored values fall back to Standard.
        self.detectionDetail = defaults.string(forKey: Self.detailKey)
            .flatMap(DetectionDetail.init(rawValue:)) ?? .standard
    }

    /// In-memory settings for previews and unit tests: fixed starting value,
    /// nothing persisted.
    init(previewDetail: DetectionDetail) {
        self.defaults = nil
        self.detectionDetail = previewDetail
    }
}
