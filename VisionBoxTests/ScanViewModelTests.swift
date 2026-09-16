//
//  ScanViewModelTests.swift
//  VisionBoxTests
//

import UIKit
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

private nonisolated struct DetectionErrorService: ObjectDetectionService {
    let error: DetectionError

    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        throw error
    }
}

private nonisolated struct NeverFinishingService: ObjectDetectionService {
    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        try await Task.sleep(for: .seconds(60))
        return []
    }
}

/// Records which API keys the live-service factory was asked for.
@MainActor
private final class LiveServiceRecorder {
    private(set) var requestedKeys: [String] = []
    private let service: any ObjectDetectionService

    init(service: any ObjectDetectionService) {
        self.service = service
    }

    func factory(_ key: String) -> any ObjectDetectionService {
        requestedKeys.append(key)
        return service
    }
}

@MainActor
struct ScanViewModelTests {

    private func makeViewModel(
        demo: any ObjectDetectionService = DemoDetectionService(),
        keyStore: GeminiKeyStore? = nil,
        live: any ObjectDetectionService = SucceedingService(objects: []),
        state: ScanViewModel.State = .idle
    ) -> ScanViewModel {
        ScanViewModel(
            demoService: demo,
            keyStore: keyStore ?? GeminiKeyStore(previewKey: nil),
            liveService: { _ in live },
            state: state
        )
    }

    private func tinyImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    // MARK: - Demo flow

    @Test func demoAnalysisMovesThroughAnalyzingToResults() async throws {
        let expected = DemoScene.desk.detections
        let viewModel = makeViewModel(demo: SucceedingService(objects: expected))

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

    @Test func demoServiceFailureShowsError() async {
        let viewModel = makeViewModel(demo: FailingService())

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
        let viewModel = makeViewModel(demo: SucceedingService(objects: []))

        viewModel.analyzeDemoScene(.kitchen)
        await viewModel.analysisTask?.value

        guard case .results(_, let objects) = viewModel.state else {
            Issue.record("Expected .results, got \(viewModel.state)")
            return
        }
        #expect(objects.isEmpty)
    }

    @Test func demoModeNeverNeedsAKey() async {
        // Demo analysis works with no key configured at all.
        let viewModel = makeViewModel(
            demo: SucceedingService(objects: DemoScene.desk.detections),
            keyStore: GeminiKeyStore(previewKey: nil)
        )

        viewModel.analyzeDemoScene(.desk)
        await viewModel.analysisTask?.value

        guard case .results = viewModel.state else {
            Issue.record("Expected .results, got \(viewModel.state)")
            return
        }
    }

    // MARK: - Credential availability propagation

    @Test func availabilityFollowsTheKeyStore() {
        #expect(!makeViewModel(keyStore: GeminiKeyStore(previewKey: nil)).isLiveAnalysisAvailable)
        #expect(makeViewModel(keyStore: GeminiKeyStore(previewKey: "test-key")).isLiveAnalysisAvailable)
    }

    @Test func savingAndRemovingAKeyUpdatesAvailabilityImmediately() throws {
        let keyStore = GeminiKeyStore(previewKey: nil)
        let viewModel = makeViewModel(keyStore: keyStore)

        #expect(!viewModel.isLiveAnalysisAvailable)
        try keyStore.save("test-key")
        #expect(viewModel.isLiveAnalysisAvailable)
        try keyStore.remove()
        #expect(!viewModel.isLiveAnalysisAvailable)
    }

    @Test func analysisUsesTheCurrentKeyNotTheKeyAtCreationTime() async throws {
        let keyStore = GeminiKeyStore(previewKey: "first-key")
        let recorder = LiveServiceRecorder(service: SucceedingService(objects: []))
        let viewModel = ScanViewModel(
            demoService: DemoDetectionService(),
            keyStore: keyStore,
            liveService: recorder.factory,
            state: .photoReady(tinyImage())
        )

        // The user replaces the key in Settings before analyzing.
        try keyStore.save("second-key")

        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value

        #expect(recorder.requestedKeys == ["second-key"])
    }

    // MARK: - Live photo flow

    @Test func analyzePhotoRunsThroughTheLiveService() async throws {
        let expected = DemoScene.desk.detections
        let viewModel = makeViewModel(
            keyStore: GeminiKeyStore(previewKey: "test-key"),
            live: SucceedingService(objects: expected),
            state: .photoReady(tinyImage())
        )

        viewModel.analyzePhoto()
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

    @Test func analyzePhotoWithoutAKeyExplainsInsteadOfPretending() {
        let keyStore = GeminiKeyStore(previewKey: nil)
        let recorder = LiveServiceRecorder(service: SucceedingService(objects: []))
        let viewModel = ScanViewModel(
            demoService: DemoDetectionService(),
            keyStore: keyStore,
            liveService: recorder.factory,
            state: .photoReady(tinyImage())
        )

        viewModel.analyzePhoto()

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error, got \(viewModel.state)")
            return
        }
        #expect(message == DetectionError.missingAPIKey.userMessage)
        #expect(recorder.requestedKeys.isEmpty)
    }

    @Test func liveFailureSurfacesTheTypedUserMessage() async {
        let viewModel = makeViewModel(
            keyStore: GeminiKeyStore(previewKey: "test-key"),
            live: DetectionErrorService(error: .rateLimited),
            state: .photoReady(tinyImage())
        )

        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error, got \(viewModel.state)")
            return
        }
        #expect(message == DetectionError.rateLimited.userMessage)
    }

    // MARK: - Cancellation

    @Test func resetCancelsAnalysisAndReturnsToIdle() async throws {
        let viewModel = makeViewModel(demo: NeverFinishingService())

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
        let viewModel = makeViewModel(demo: NeverFinishingService())

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
