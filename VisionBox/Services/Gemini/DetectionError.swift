//
//  DetectionError.swift
//  VisionBox
//

import Foundation

/// Typed failures for the live Gemini pipeline.
///
/// `userMessage` is the only text shown in the UI. No case ever carries the
/// API key, request bodies, raw provider error text, or image data.
nonisolated enum DetectionError: Error, Equatable {
    /// No Gemini API key is stored on this device.
    case missingAPIKey
    /// The API rejected the key (HTTP 401/403).
    case unauthorized
    /// Too many requests (HTTP 429).
    case rateLimited
    /// Gemini-side failure (HTTP 5xx).
    case server(statusCode: Int)
    /// Transport-level failure.
    case network(URLError.Code?)
    /// The response was missing usable output (including refusals) or had an
    /// unexpected status.
    case invalidResponse
    /// The response arrived but couldn't be decoded as structured detections.
    case decoding
    /// The selected image couldn't be prepared for upload.
    case imagePreparation

    var userMessage: String {
        switch self {
        case .missingAPIKey:
            "A Gemini API key is required to analyze your own photos. Key setup is coming to Settings."
        case .unauthorized:
            "Your Gemini API key wasn't accepted. Please check it and try again."
        case .rateLimited:
            "Gemini is handling too many requests right now. Wait a moment and try again."
        case .server:
            "Gemini is temporarily unavailable. Please try again shortly."
        case .network:
            "A network problem interrupted the analysis. Check your connection and try again."
        case .invalidResponse:
            "Gemini couldn't analyze this image. Please try again."
        case .decoding:
            "Gemini returned an unexpected response. Please try again."
        case .imagePreparation:
            "This photo couldn't be prepared for analysis. Try a different one."
        }
    }
}
