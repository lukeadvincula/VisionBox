//
//  DetectionSettings.swift
//  VisionBox
//

import Foundation
import Observation

/// The user's detection preferences — ordinary, non-sensitive settings.
///
/// Backed by UserDefaults (the Keychain remains exclusively for the Gemini
/// API key). Observable and shared via `AppDependencies`, so changing the
/// mode on the Scan screen applies to the next analysis immediately.
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
        self.detectionDetail = Self.detail(fromStored: defaults.string(forKey: Self.detailKey))
    }

    /// In-memory settings for previews and unit tests: fixed starting value,
    /// nothing persisted.
    init(previewDetail: DetectionDetail) {
        self.defaults = nil
        self.detectionDetail = previewDetail
    }

    /// Absent, unknown, or corrupt stored values fall back to Generic.
    /// "standard" was Generic's raw value in pre-release development builds;
    /// mapping it here is the whole migration.
    private static func detail(fromStored rawValue: String?) -> DetectionDetail {
        if rawValue == "standard" {
            return .generic
        }
        return rawValue.flatMap(DetectionDetail.init(rawValue:)) ?? .generic
    }
}
