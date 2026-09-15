//
//  ImageProcessing.swift
//  VisionBox
//

import UIKit

/// Prepares images for Gemini upload: orientation-normalized, downscaled,
/// JPEG-encoded.
///
/// The full picture is always preserved — scaled, never cropped — so
/// normalized bounding boxes keep referring to the entire image, and the
/// uploaded pixels share the exact visual orientation of the image shown in
/// Results.
nonisolated enum ImageProcessing {

    /// Longest edge sent to Gemini. Larger wastes upload size, tokens, and
    /// latency for no detection benefit; much smaller starts costing
    /// small-object accuracy. A starting point, easy to tune here.
    static let maxDimension: CGFloat = 1536

    static let jpegQuality: CGFloat = 0.85

    /// Returns upload-ready JPEG data. Runs off the main actor — decoding and
    /// re-rendering large photos is expensive.
    @concurrent
    static func prepareForUpload(_ image: UIImage) async throws -> Data {
        // `UIImage.size` already accounts for EXIF orientation; multiplying
        // by `scale` yields the oriented pixel dimensions.
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let target = targetSize(for: pixelSize)
        guard target.width >= 1, target.height >= 1 else {
            throw DetectionError.imagePreparation
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // Drawing honors imageOrientation, so the rendered pixels come
            // out upright (.up) regardless of the source's EXIF orientation.
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        guard let data = normalized.jpegData(compressionQuality: jpegQuality) else {
            throw DetectionError.imagePreparation
        }
        return data
    }

    /// The upload size for a source size: capped to `maxDimension` on the
    /// longest edge, aspect ratio preserved, never upscaled.
    static func targetSize(for size: CGSize, maxDimension: CGFloat = maxDimension) -> CGSize {
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxDimension else { return size }
        let scale = maxDimension / longestEdge
        return CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
    }
}
