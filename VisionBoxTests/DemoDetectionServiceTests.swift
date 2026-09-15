//
//  DemoDetectionServiceTests.swift
//  VisionBoxTests
//

import Foundation
import Testing
@testable import VisionBox

struct DemoDetectionServiceTests {

    @Test func everySceneHasLoadableAssetsAndFixtures() {
        for scene in DemoScene.all {
            #expect(scene.image != nil, "Missing bundled image for \(scene.id)")
            #expect(scene.imageData != nil, "Missing bundled image data for \(scene.id)")
            #expect(!scene.detections.isEmpty, "No fixtures for \(scene.id)")
        }
    }

    @Test func fixtureBoxesLieWithinTheUnitRect() {
        for scene in DemoScene.all {
            for object in scene.detections {
                let box = object.boundingBox
                let comment: Comment = "Out-of-range box for \(object.label) in \(scene.id)"
                #expect(box.x >= 0 && box.y >= 0, comment)
                #expect(box.width > 0 && box.height > 0, comment)
                #expect(box.x + box.width <= 1 && box.y + box.height <= 1, comment)
            }
        }
    }

    @Test func returnsTheMatchingDetectionsForEachSceneImage() async throws {
        let service = DemoDetectionService()
        for scene in DemoScene.all {
            let imageData = try #require(scene.imageData)
            let objects = try await service.detectObjects(in: imageData)
            #expect(objects == scene.detections)
        }
    }

    @Test func resultsAreDeterministicAcrossCalls() async throws {
        let service = DemoDetectionService()
        let imageData = try #require(DemoScene.desk.imageData)
        let first = try await service.detectObjects(in: imageData)
        let second = try await service.detectObjects(in: imageData)
        #expect(first == second)
    }

    @Test func throwsForUnrecognizedImageData() async {
        await #expect(throws: DemoDetectionError.self) {
            _ = try await DemoDetectionService().detectObjects(in: Data([0x00, 0x01]))
        }
    }

    @Test func cancellationStopsAnalysis() async {
        let task = Task {
            try await DemoDetectionService().detectObjects(in: Data())
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
