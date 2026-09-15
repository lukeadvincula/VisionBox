//
//  ImageGeometryTests.swift
//  VisionBoxTests
//

import CoreGraphics
import Testing
@testable import VisionBox

struct ImageGeometryTests {

    // MARK: - Normalized box → rendered rectangle

    @Test func rectScalesBoxByContainerSize() {
        let box = BoundingBox(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let rect = ImageGeometry.rect(for: box, in: CGSize(width: 200, height: 100))
        #expect(rect == CGRect(x: 50, y: 50, width: 100, height: 25))
    }

    @Test func differentContainerSizesProduceProportionallyEquivalentRects() {
        let box = BoundingBox(x: 0.125, y: 0.25, width: 0.5, height: 0.5)
        let small = ImageGeometry.rect(for: box, in: CGSize(width: 100, height: 80))
        let large = ImageGeometry.rect(for: box, in: CGSize(width: 400, height: 320))

        // Quadrupling the container quadruples the rect exactly — the property
        // that keeps boxes aligned while the layout resizes.
        #expect(large.origin.x == small.origin.x * 4)
        #expect(large.origin.y == small.origin.y * 4)
        #expect(large.width == small.width * 4)
        #expect(large.height == small.height * 4)
    }

    @Test func rectClampsOutOfRangeBoxToImageBounds() {
        let box = BoundingBox(x: 0.75, y: -0.25, width: 0.5, height: 0.5)
        let rect = ImageGeometry.rect(for: box, in: CGSize(width: 100, height: 100))
        #expect(rect == CGRect(x: 75, y: 0, width: 25, height: 25))
    }

    @Test func rectInZeroSizeContainerIsZero() {
        let box = BoundingBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        #expect(ImageGeometry.rect(for: box, in: .zero) == .zero)
    }

    // MARK: - View point → normalized point

    @Test func normalizesPointByContainerSize() {
        let point = ImageGeometry.normalizedPoint(CGPoint(x: 50, y: 25), in: CGSize(width: 200, height: 100))
        #expect(point == CGPoint(x: 0.25, y: 0.25))
    }

    @Test func normalizedPointIsEquivalentAcrossContainerSizes() {
        let small = ImageGeometry.normalizedPoint(CGPoint(x: 25, y: 20), in: CGSize(width: 100, height: 80))
        let large = ImageGeometry.normalizedPoint(CGPoint(x: 100, y: 80), in: CGSize(width: 400, height: 320))
        #expect(small == large)
    }

    @Test func normalizedPointClampsToUnitRect() {
        let size = CGSize(width: 100, height: 100)
        #expect(ImageGeometry.normalizedPoint(CGPoint(x: -20, y: 150), in: size) == CGPoint(x: 0, y: 1))
        #expect(ImageGeometry.normalizedPoint(CGPoint(x: 150, y: -20), in: size) == CGPoint(x: 1, y: 0))
    }

    @Test func zeroSizeContainerMapsToOriginInsteadOfNaN() {
        #expect(ImageGeometry.normalizedPoint(CGPoint(x: 50, y: 50), in: .zero) == .zero)
    }
}
