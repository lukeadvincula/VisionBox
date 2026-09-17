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

/// Fails the first call with a transient error, then succeeds — the shape of
/// a real-world Try Again recovery.
private actor FlakyOnceService: ObjectDetectionService {
    private var hasFailedOnce = false
    private let objects: [DetectedObject]

    init(objects: [DetectedObject]) {
        self.objects = objects
    }

    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        if !hasFailedOnce {
            hasFailedOnce = true
            throw DetectionError.server(statusCode: 503)
        }
        return objects
    }
}

/// Records which API keys and detail levels the live-service factory was
/// asked for.
@MainActor
private final class LiveServiceRecorder {
    private(set) var requestedKeys: [String] = []
    private(set) var requestedDetails: [DetectionDetail] = []
    private let service: any ObjectDetectionService

    init(service: any ObjectDetectionService) {
        self.service = service
    }

    func factory(_ key: String, _ detail: DetectionDetail) -> any ObjectDetectionService {
        requestedKeys.append(key)
        requestedDetails.append(detail)
        return service
    }
}

@MainActor
struct ScanViewModelTests {

    private func makeViewModel(
        demo: any ObjectDetectionService = DemoDetectionService(),
        keyStore: GeminiKeyStore? = nil,
        settings: DetectionSettings? = nil,
        live: any ObjectDetectionService = SucceedingService(objects: []),
        state: ScanViewModel.State = .idle
    ) -> ScanViewModel {
        ScanViewModel(
            demoService: demo,
            keyStore: keyStore ?? GeminiKeyStore(previewKey: nil),
            settings: settings ?? DetectionSettings(previewDetail: .standard),
            liveService: { _, _ in live },
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
            settings: DetectionSettings(previewDetail: .standard),
            liveService: recorder.factory,
            state: .photoReady(tinyImage())
        )

        // The user replaces the key in Settings before analyzing.
        try keyStore.save("second-key")

        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value

        #expect(recorder.requestedKeys == ["second-key"])
    }

    @Test func analysisUsesTheCurrentDetectionDetail() async {
        let settings = DetectionSettings(previewDetail: .standard)
        let recorder = LiveServiceRecorder(service: SucceedingService(objects: []))
        let viewModel = ScanViewModel(
            demoService: DemoDetectionService(),
            keyStore: GeminiKeyStore(previewKey: "test-key"),
            settings: settings,
            liveService: recorder.factory,
            state: .photoReady(tinyImage())
        )

        // The user switches to Detailed in Settings before analyzing.
        settings.detectionDetail = .detailed

        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value

        #expect(recorder.requestedDetails == [.detailed])
    }

    @Test func tryAgainUsesTheDetectionDetailCurrentAtRetryTime() async {
        // Try Again is a new user-initiated analysis: a Settings change made
        // after the failure applies to it.
        let settings = DetectionSettings(previewDetail: .standard)
        let recorder = LiveServiceRecorder(service: DetectionErrorService(error: .server(statusCode: 503)))
        let viewModel = ScanViewModel(
            demoService: DemoDetectionService(),
            keyStore: GeminiKeyStore(previewKey: "test-key"),
            settings: settings,
            liveService: recorder.factory,
            state: .photoReady(tinyImage())
        )

        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value
        #expect(recorder.requestedDetails == [.standard])

        settings.detectionDetail = .detailed
        viewModel.retryAnalysis()
        await viewModel.analysisTask?.value

        #expect(recorder.requestedDetails == [.standard, .detailed])
    }

    // MARK: - Camera capture

    @Test func capturedImageTransitionsToPhotoReady() {
        let viewModel = makeViewModel()

        viewModel.setCapturedImage(tinyImage())

        guard case .photoReady = viewModel.state else {
            Issue.record("Expected .photoReady, got \(viewModel.state)")
            return
        }
    }

    @Test func capturedImageReplacesInFlightWorkAndExistingPhoto() async throws {
        let viewModel = makeViewModel(demo: NeverFinishingService())

        viewModel.analyzeDemoScene(.desk)
        let previousTask = try #require(viewModel.analysisTask)

        let replacement = tinyImage()
        viewModel.setCapturedImage(replacement)

        #expect(previousTask.isCancelled)
        guard case .photoReady(let image) = viewModel.state else {
            Issue.record("Expected .photoReady, got \(viewModel.state)")
            return
        }
        #expect(image === replacement)

        // The cancelled task must not clobber the captured photo's state.
        await previousTask.value
        guard case .photoReady = viewModel.state else {
            Issue.record("Expected .photoReady after cancelled task finished, got \(viewModel.state)")
            return
        }
    }

    @Test func capturedImageUsesTheSameAnalysisPathAsPhotosSelections() async {
        // A camera capture converges into photoReady and flows through the
        // identical analyzePhoto() → live-service pipeline.
        let expected = DemoScene.desk.detections
        let viewModel = makeViewModel(
            keyStore: GeminiKeyStore(previewKey: "test-key"),
            live: SucceedingService(objects: expected)
        )

        viewModel.setCapturedImage(tinyImage())
        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value

        guard case .results(_, let objects) = viewModel.state else {
            Issue.record("Expected .results, got \(viewModel.state)")
            return
        }
        #expect(objects == expected)
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
            settings: DetectionSettings(previewDetail: .standard),
            liveService: recorder.factory,
            state: .photoReady(tinyImage())
        )

        viewModel.analyzePhoto()

        guard case .error(let message, let image) = viewModel.state else {
            Issue.record("Expected .error, got \(viewModel.state)")
            return
        }
        #expect(message == DetectionError.missingAPIKey.userMessage)
        #expect(image != nil)
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

        guard case .error(let message, _) = viewModel.state else {
            Issue.record("Expected .error, got \(viewModel.state)")
            return
        }
        #expect(message == DetectionError.rateLimited.userMessage)
    }

    // MARK: - Failure recovery

    @Test func analysisFailureRetainsTheSelectedImage() async {
        let original = tinyImage()
        let viewModel = makeViewModel(
            keyStore: GeminiKeyStore(previewKey: "test-key"),
            live: DetectionErrorService(error: .server(statusCode: 503)),
            state: .photoReady(original)
        )

        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value

        guard case .error(_, .some(let retained)) = viewModel.state else {
            Issue.record("Expected .error with a retained image, got \(viewModel.state)")
            return
        }
        #expect(retained === original)
    }

    @Test func tryAgainReanalyzesTheSameImageToResults() async {
        let expected = DemoScene.desk.detections
        let viewModel = makeViewModel(
            keyStore: GeminiKeyStore(previewKey: "test-key"),
            live: FlakyOnceService(objects: expected),
            state: .photoReady(tinyImage())
        )

        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value
        guard case .error(_, .some) = viewModel.state else {
            Issue.record("Expected .error with retained image, got \(viewModel.state)")
            return
        }

        viewModel.retryAnalysis()
        guard case .analyzing = viewModel.state else {
            Issue.record("Expected .analyzing after Try Again, got \(viewModel.state)")
            return
        }

        await viewModel.analysisTask?.value
        guard case .results(_, let objects) = viewModel.state else {
            Issue.record("Expected .results after retry, got \(viewModel.state)")
            return
        }
        #expect(objects == expected)
    }

    @Test func retryAnalysisDoesNothingWithoutARetainedImage() {
        let viewModel = makeViewModel(state: .error(message: "Photo failed to load.", image: nil))

        viewModel.retryAnalysis()

        guard case .error = viewModel.state else {
            Issue.record("Expected unchanged .error, got \(viewModel.state)")
            return
        }
    }

    @Test func changingTheImageAfterFailureWorks() async {
        let viewModel = makeViewModel(
            keyStore: GeminiKeyStore(previewKey: "test-key"),
            live: DetectionErrorService(error: .rateLimited),
            state: .photoReady(tinyImage())
        )

        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value

        let replacement = tinyImage()
        viewModel.setCapturedImage(replacement)
        guard case .photoReady(let image) = viewModel.state else {
            Issue.record("Expected .photoReady, got \(viewModel.state)")
            return
        }
        #expect(image === replacement)
    }

    @Test func resetAfterFailureReturnsToIdle() async {
        let viewModel = makeViewModel(
            keyStore: GeminiKeyStore(previewKey: "test-key"),
            live: DetectionErrorService(error: .rateLimited),
            state: .photoReady(tinyImage())
        )

        viewModel.analyzePhoto()
        await viewModel.analysisTask?.value
        viewModel.reset()

        guard case .idle = viewModel.state else {
            Issue.record("Expected .idle, got \(viewModel.state)")
            return
        }
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
