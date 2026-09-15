//
//  ImageProcessingTests.swift
//  VisionBoxTests
//

import UIKit
import Testing
@testable import VisionBox

struct ImageProcessingTests {

    // MARK: - Target-size calculation (pure)

    @Test func capsLandscapeLongestEdge() {
        let target = ImageProcessing.targetSize(for: CGSize(width: 4000, height: 3000), maxDimension: 1536)
        #expect(target == CGSize(width: 1536, height: 1152))
    }

    @Test func capsPortraitLongestEdge() {
        let target = ImageProcessing.targetSize(for: CGSize(width: 3000, height: 4000), maxDimension: 1536)
        #expect(target == CGSize(width: 1152, height: 1536))
    }

    @Test func neverUpscalesSmallImages() {
        let size = CGSize(width: 800, height: 600)
        #expect(ImageProcessing.targetSize(for: size, maxDimension: 1536) == size)
    }

    @Test func preservesAspectRatioWithinRounding() {
        let source = CGSize(width: 3021, height: 1417)
        let target = ImageProcessing.targetSize(for: source, maxDimension: 1536)
        #expect(max(target.width, target.height) == 1536)
        let sourceRatio = source.width / source.height
        let targetRatio = target.width / target.height
        #expect(abs(sourceRatio - targetRatio) < 0.01)
    }

    // MARK: - Upload preparation

    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func producesDecodableJPEGAtOriginalSizeWhenSmall() async throws {
        let data = try await ImageProcessing.prepareForUpload(solidImage(width: 200, height: 100))

        // JPEG SOI marker.
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width * decoded.scale == 200)
        #expect(decoded.size.height * decoded.scale == 100)
    }

    @Test func downscalesLargeImagesPreservingAspect() async throws {
        let data = try await ImageProcessing.prepareForUpload(solidImage(width: 4000, height: 2000))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width * decoded.scale == 1536)
        #expect(decoded.size.height * decoded.scale == 768)
    }

    @Test func normalizesEXIFOrientationToUp() async throws {
        // A 200×100 pixel buffer tagged .right displays as 100×200; the
        // prepared upload must contain upright pixels of that displayed size.
        let source = solidImage(width: 200, height: 100)
        let cgImage = try #require(source.cgImage)
        let rotated = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
        #expect(rotated.size == CGSize(width: 100, height: 200))

        let data = try await ImageProcessing.prepareForUpload(rotated)
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.imageOrientation == .up)
        #expect(decoded.size.width * decoded.scale == 100)
        #expect(decoded.size.height * decoded.scale == 200)
    }
}
