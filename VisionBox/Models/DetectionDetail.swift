//
//  DetectionDetail.swift
//  VisionBox
//

/// How specifically Gemini should identify detected objects.
///
/// Standard names the general product or object ("Game Controller");
/// Detailed adds brand/model/variant when the photo visibly supports it
/// ("DualSense Wireless Controller") and falls back to the general name
/// otherwise. Affects only the detection prompt — never the response
/// schema, the Results UI, or Demo Mode.
///
/// Raw values are persisted in UserDefaults; keep them stable.
nonisolated enum DetectionDetail: String, CaseIterable, Sendable {
    case standard
    case detailed
}
