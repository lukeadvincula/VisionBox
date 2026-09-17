//
//  BoundingBoxTests.swift
//  VisionBoxTests
//

import CoreGraphics
import Testing
@testable import VisionBox

struct BoundingBoxTests {

    // MARK: - Area

    @Test func areaIsWidthTimesHeight() {
        let box = BoundingBox(x: 0, y: 0, width: 0.5, height: 0.25)
        #expect(box.area == 0.125)
    }

    // MARK: - Clamping

    @Test func clampingLeavesValidBoxUnchanged() {
        let box = BoundingBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        #expect(box.clamped() == box)
    }

    @Test func clampingTrimsBoxExtendingPastEdges() {
        let box = BoundingBox(x: 0.75, y: 0.5, width: 0.5, height: 1)
        #expect(box.clamped() == BoundingBox(x: 0.75, y: 0.5, width: 0.25, height: 0.5))
    }

    @Test func clampingTrimsBoxStartingBeforeOrigin() {
        // The clamped box is the intersection with the unit rect: the part
        // hanging off the top-left is cut away, not shifted inside.
        let box = BoundingBox(x: -0.25, y: -0.5, width: 0.5, height: 1)
        #expect(box.clamped() == BoundingBox(x: 0, y: 0, width: 0.25, height: 0.5))
    }

    @Test func clampingCollapsesBoxEntirelyOutsideUnitRect() {
        let box = BoundingBox(x: 1.5, y: 1.5, width: 0.5, height: 0.5)
        #expect(box.clamped().area == 0)
    }

    @Test func clampingCollapsesNegativeSizeToZero() {
        let box = BoundingBox(x: 0.5, y: 0.5, width: -0.25, height: -0.25)
        #expect(box.clamped() == BoundingBox(x: 0.5, y: 0.5, width: 0, height: 0))
    }

    // MARK: - Containment

    @Test func containsPointInsideBox() {
        let box = BoundingBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        #expect(box.contains(CGPoint(x: 0.5, y: 0.5)))
    }

    @Test func doesNotContainPointOutsideBox() {
        let box = BoundingBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        #expect(!box.contains(CGPoint(x: 0.1, y: 0.5)))
        #expect(!box.contains(CGPoint(x: 0.5, y: 0.8)))
    }

    @Test func containmentIsEdgeInclusive() {
        let box = BoundingBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        #expect(box.contains(CGPoint(x: 0.25, y: 0.25)))
        #expect(box.contains(CGPoint(x: 0.75, y: 0.75)))
    }

    // MARK: - Hit testing

    private let large = DetectedObject(
        label: "Notebook",
        boundingBox: BoundingBox(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
    )
    private let small = DetectedObject(
        label: "Pen",
        boundingBox: BoundingBox(x: 0.4, y: 0.4, width: 0.2, height: 0.1)
    )

    @Test func hitTestFindsContainingObject() {
        let hit = [large, small].object(at: CGPoint(x: 0.25, y: 0.25))
        #expect(hit == large)
    }

    @Test func hitTestReturnsNilWhenNoObjectContainsPoint() {
        #expect([large, small].object(at: CGPoint(x: 0.05, y: 0.05)) == nil)
    }

    @Test func hitTestReturnsNilForEmptyArray() {
        #expect([DetectedObject]().object(at: CGPoint(x: 0.5, y: 0.5)) == nil)
    }

    @Test func smallestBoxWinsWhenBoxesOverlap() {
        // The point is inside both boxes; the nested smaller object should win
        // regardless of array order.
        let point = CGPoint(x: 0.5, y: 0.45)
        #expect([large, small].object(at: point) == small)
        #expect([small, large].object(at: point) == small)
    }

    // MARK: - Rendered-space hit testing with minimum touch targets

    private let renderedSize = CGSize(width: 400, height: 400)

    @Test func tinyBoxGetsAMinimumHitTarget() {
        // Rendered at 400×400 this box is only 4 pt wide; its hit area
        // expands to 44 pt so it stays tappable.
        let tiny = DetectedObject(
            label: "Coin",
            boundingBox: BoundingBox(x: 0.5, y: 0.5, width: 0.01, height: 0.01)
        )

        let nearMiss = CGPoint(x: 0.5 * 400 + 17, y: 0.5 * 400)
        #expect([tiny].object(at: nearMiss, renderedSize: renderedSize) == tiny)

        let farMiss = CGPoint(x: 0.5 * 400 + 60, y: 0.5 * 400)
        #expect([tiny].object(at: farMiss, renderedSize: renderedSize) == nil)
    }

    @Test func largeBoxHitAreaIsNotExpanded() {
        // Rendered span: 80...320 on both axes — a point just outside misses.
        let bigBox = DetectedObject(
            label: "Table",
            boundingBox: BoundingBox(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        )
        #expect([bigBox].object(at: CGPoint(x: 330, y: 200), renderedSize: renderedSize) == nil)
        #expect([bigBox].object(at: CGPoint(x: 300, y: 200), renderedSize: renderedSize) == bigBox)
    }

    @Test func expandedTargetsPreserveSmallestAreaWins() {
        let bigBox = DetectedObject(
            label: "Notebook",
            boundingBox: BoundingBox(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        )
        let tiny = DetectedObject(
            label: "Coin",
            boundingBox: BoundingBox(x: 0.5, y: 0.5, width: 0.01, height: 0.01)
        )
        // Inside the big box AND inside the tiny box's expanded target:
        // the smaller actual box still wins, in either array order.
        let point = CGPoint(x: 0.5 * 400 + 12, y: 0.5 * 400 + 8)
        #expect([bigBox, tiny].object(at: point, renderedSize: renderedSize) == tiny)
        #expect([tiny, bigBox].object(at: point, renderedSize: renderedSize) == tiny)
    }
}
