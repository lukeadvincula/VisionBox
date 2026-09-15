//
//  ScanViewModelTests.swift
//  VisionBoxTests
//

import Foundation
import Testing
@testable import VisionBox

// Stub services driven through the same ObjectDetectionService seam.

private nonisolated struct SucceedingService: ObjectDetectionService {
    let objects: [DetectedObject]

    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        objects
    }
}

private nonisolated struct FailingService: ObjectDetectionService {
    struct Failure: Error {}

    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        throw Failure()
    }
}

private nonisolated struct NeverFinishingService: ObjectDetectionService {
    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        try await Task.sleep(for: .seconds(60))
        return []
    }
}

@MainActor
struct ScanViewModelTests {

    @Test func demoAnalysisMovesThroughAnalyzingToResults() async throws {
        let expected = DemoScene.desk.detections
        let viewModel = ScanViewModel(detectionService: SucceedingService(objects: expected))

        viewModel.analyzeDemoScene(.desk)
        guard case .analyzing = viewModel.state else {
            Issue.record("Expected .analyzing, got \(viewModel.state)")
            return
        }

        await viewModel.analysisTask?.value
        guard case .results(_, let objects) = viewModel.state else {
            Issue.record("Expected .results, got \(viewModel.state)")
            return
        }
        #expect(objects == expected)
    }

    @Test func serviceFailureShowsError() async {
        let viewModel = ScanViewModel(detectionService: FailingService())

        viewModel.analyzeDemoScene(.desk)
        await viewModel.analysisTask?.value

        guard case .error = viewModel.state else {
            Issue.record("Expected .error, got \(viewModel.state)")
            return
        }
    }

    @Test func emptyDetectionsStillProduceResults() async {
        // Zero detections is a normal outcome that drives the empty state,
        // not an error.
        let viewModel = ScanViewModel(detectionService: SucceedingService(objects: []))

        viewModel.analyzeDemoScene(.kitchen)
        await viewModel.analysisTask?.value

        guard case .results(_, let objects) = viewModel.state else {
            Issue.record("Expected .results, got \(viewModel.state)")
            return
        }
        #expect(objects.isEmpty)
    }

    @Test func resetCancelsAnalysisAndReturnsToIdle() async throws {
        let viewModel = ScanViewModel(detectionService: NeverFinishingService())

        viewModel.analyzeDemoScene(.desk)
        let task = try #require(viewModel.analysisTask)

        viewModel.reset()
        #expect(task.isCancelled)
        guard case .idle = viewModel.state else {
            Issue.record("Expected .idle, got \(viewModel.state)")
            return
        }

        // The cancelled task must not clobber the state it was superseded by.
        await task.value
        guard case .idle = viewModel.state else {
            Issue.record("Expected .idle after cancelled task finished, got \(viewModel.state)")
            return
        }
    }

    @Test func newAnalysisCancelsThePreviousOne() async throws {
        let viewModel = ScanViewModel(detectionService: NeverFinishingService())

        viewModel.analyzeDemoScene(.desk)
        let firstTask = try #require(viewModel.analysisTask)

        viewModel.analyzeDemoScene(.kitchen)
        #expect(firstTask.isCancelled)
        #expect(viewModel.analysisTask != nil)

        guard case .analyzing = viewModel.state else {
            Issue.record("Expected .analyzing, got \(viewModel.state)")
            return
        }
        viewModel.reset()
    }
}
