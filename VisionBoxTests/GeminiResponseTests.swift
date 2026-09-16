//
//  GeminiResponseTests.swift
//  VisionBoxTests
//

import Foundation
import Testing
@testable import VisionBox

/// Sanitized local fixtures mimicking Interactions API responses.
/// No credentials, no user data, no base64 images.
private enum Fixture {

    static func envelope(outputText: String, status: String = "completed") -> Data {
        let escaped = outputText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return Data("""
        {
          "id": "interaction_fixture",
          "status": "\(status)",
          "steps": [
            { "type": "model_output", "content": [ { "type": "text", "text": "\(escaped)" } ] }
          ]
        }
        """.utf8)
    }

    static let twoObjects = envelope(outputText: """
        [
          {"label": "Coffee Mug", "category": "Kitchenware", "box_2d": [100, 200, 300, 400]},
          {"label": "Laptop", "box_2d": [50, 500, 650, 950]}
        ]
        """)

    static let zeroObjects = envelope(outputText: "[]")

    /// One valid detection among malformed ones: wrong coordinate count,
    /// reversed edges, zero height, and fully outside the unit rect.
    static let mixedValidity = envelope(outputText: """
        [
          {"label": "Keeper", "box_2d": [250, 250, 750, 750]},
          {"label": "Three Coordinates", "box_2d": [1, 2, 3]},
          {"label": "Reversed Edges", "box_2d": [300, 400, 100, 200]},
          {"label": "Zero Height", "box_2d": [100, 200, 100, 400]},
          {"label": "Fully Outside", "box_2d": [1200, 1200, 1500, 1500]},
          {"label": "", "box_2d": [100, 100, 200, 200]}
        ]
        """)

    static let partiallyOutOfRange = envelope(outputText: """
        [ {"label": "Edge Hugger", "box_2d": [-100, -100, 500, 500]} ]
        """)

    static let malformedInnerJSON = envelope(outputText: "objects: mug, laptop")

    static let missingOutput = Data("""
        { "id": "interaction_fixture", "status": "completed", "steps": [] }
        """.utf8)

    static let failedStatus = Data("""
        {
          "id": "interaction_fixture",
          "status": "failed",
          "steps": [],
          "errors": [ { "code": "internal", "message": "provider detail that must never surface" } ]
        }
        """.utf8)

    static let notJSON = Data("this is not an interactions response".utf8)
}

struct GeminiResponseTests {

    /// Float-safe box comparison: mapping divides and subtracts, so exact
    /// binary equality is too strict.
    private func expectBox(
        _ box: BoundingBox?, x: Double, y: Double, width: Double, height: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let box else {
            Issue.record("Expected a bounding box", sourceLocation: sourceLocation)
            return
        }
        let tolerance = 1e-9
        #expect(abs(box.x - x) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(box.y - y) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(box.width - width) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(box.height - height) < tolerance, sourceLocation: sourceLocation)
    }

    // MARK: - Decoding and mapping

    @Test func decodesAndMapsMultipleObjects() throws {
        let objects = try GeminiDetectionService.detections(fromResponseData: Fixture.twoObjects)
        #expect(objects.count == 2)

        let mug = try #require(objects.first)
        #expect(mug.label == "Coffee Mug")
        #expect(mug.category == "Kitchenware")
        #expect(mug.confidence == nil)
        // box_2d [100, 200, 300, 400] is [ymin, xmin, ymax, xmax] / 1000:
        expectBox(mug.boundingBox, x: 0.2, y: 0.1, width: 0.2, height: 0.2)

        let laptop = objects[1]
        #expect(laptop.category == nil)
        expectBox(laptop.boundingBox, x: 0.5, y: 0.05, width: 0.45, height: 0.6)
    }

    @Test func generatedIDsAreUniqueWithinAResultSet() throws {
        let objects = try GeminiDetectionService.detections(fromResponseData: Fixture.twoObjects)
        #expect(Set(objects.map(\.id)).count == objects.count)
    }

    @Test func zeroObjectsIsAValidEmptyResultNotAnError() throws {
        let objects = try GeminiDetectionService.detections(fromResponseData: Fixture.zeroObjects)
        #expect(objects.isEmpty)
    }

    @Test func malformedAndDegenerateBoxesAreDroppedNotCrashed() throws {
        let objects = try GeminiDetectionService.detections(fromResponseData: Fixture.mixedValidity)
        #expect(objects.map(\.label) == ["Keeper"])
        #expect(objects[0].boundingBox == BoundingBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    @Test func outOfRangeBoxesAreClampedToTheUnitRect() throws {
        let objects = try GeminiDetectionService.detections(fromResponseData: Fixture.partiallyOutOfRange)
        let box = try #require(objects.first?.boundingBox)
        #expect(box == BoundingBox(x: 0, y: 0, width: 0.5, height: 0.5))
    }

    @Test func undecodableStructuredOutputThrowsDecodingError() {
        #expect(throws: DetectionError.decoding) {
            _ = try GeminiDetectionService.detections(fromResponseData: Fixture.malformedInnerJSON)
        }
    }

    @Test func missingModelOutputThrowsInvalidResponse() {
        #expect(throws: DetectionError.invalidResponse) {
            _ = try GeminiDetectionService.detections(fromResponseData: Fixture.missingOutput)
        }
    }

    @Test func failedInteractionThrowsInvalidResponseWithoutSurfacingProviderText() {
        #expect(throws: DetectionError.invalidResponse) {
            _ = try GeminiDetectionService.detections(fromResponseData: Fixture.failedStatus)
        }
    }

    @Test func nonJSONEnvelopeThrowsDecodingError() {
        #expect(throws: DetectionError.decoding) {
            _ = try GeminiDetectionService.detections(fromResponseData: Fixture.notJSON)
        }
    }

    // MARK: - HTTP status mapping

    @Test(arguments: [
        (200, nil),
        (204, nil),
        (401, DetectionError.unauthorized),
        (403, DetectionError.unauthorized),
        (429, DetectionError.rateLimited),
        (500, DetectionError.server(statusCode: 500)),
        (503, DetectionError.server(statusCode: 503)),
        (400, DetectionError.invalidResponse),
        (404, DetectionError.invalidResponse),
    ])
    func mapsHTTPStatusCodes(statusCode: Int, expected: DetectionError?) {
        #expect(GeminiDetectionService.error(forStatusCode: statusCode) == expected)
    }

    // Google reports invalid keys as 400 + API_KEY_INVALID, not 401/403
    // (observed against the live API).
    @Test func invalidAPIKey400IsClassifiedAsUnauthorized() {
        let body = Data("""
            {
              "error": {
                "code": 400,
                "message": "API key not valid. Please pass a valid API key.",
                "status": "INVALID_ARGUMENT",
                "details": [ { "reason": "API_KEY_INVALID" } ]
              }
            }
            """.utf8)
        #expect(GeminiDetectionService.error(forStatusCode: 400, body: body) == .unauthorized)
    }

    // MARK: - Retry policy (pure)

    @Test func transientClassificationDrivesRetryEligibility() {
        #expect(DetectionError.rateLimited.isTransient)
        #expect(DetectionError.server(statusCode: 502).isTransient)
        #expect(DetectionError.network(.timedOut).isTransient)
        #expect(DetectionError.network(.networkConnectionLost).isTransient)

        #expect(!DetectionError.unauthorized.isTransient)
        #expect(!DetectionError.missingAPIKey.isTransient)
        #expect(!DetectionError.decoding.isTransient)
        #expect(!DetectionError.invalidResponse.isTransient)
        #expect(!DetectionError.imagePreparation.isTransient)
        #expect(!DetectionError.network(.notConnectedToInternet).isTransient)
    }

    @Test func exponentialDelayProgressionIsOneThenTwoSeconds() {
        #expect(GeminiDetectionService.retryDelay(afterAttempt: 1, retryAfter: nil) == .seconds(1))
        #expect(GeminiDetectionService.retryDelay(afterAttempt: 2, retryAfter: nil) == .seconds(2))
    }

    @Test func serverRetryAfterWinsButIsCapped() {
        #expect(GeminiDetectionService.retryDelay(afterAttempt: 1, retryAfter: .seconds(5)) == .seconds(5))
        #expect(
            GeminiDetectionService.retryDelay(afterAttempt: 1, retryAfter: .seconds(3600))
                == GeminiDetectionService.maxRetryDelay
        )
    }

    @Test func retryAfterHeaderParsing() throws {
        let url = try #require(URL(string: "https://example.com"))
        func response(_ headers: [String: String]) throws -> HTTPURLResponse {
            try #require(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers))
        }
        #expect(try GeminiDetectionService.retryAfter(from: response(["Retry-After": "5"])) == .seconds(5))
        #expect(try GeminiDetectionService.retryAfter(from: response(["Retry-After": " 2.5 "])) == .seconds(2.5))
        #expect(try GeminiDetectionService.retryAfter(from: response(["Retry-After": "soon"])) == nil)
        #expect(try GeminiDetectionService.retryAfter(from: response(["Retry-After": "-1"])) == nil)
        #expect(try GeminiDetectionService.retryAfter(from: response([:])) == nil)
        #expect(GeminiDetectionService.retryAfter(from: nil) == nil)
    }

    @Test func other400BodiesRemainInvalidResponse() {
        let body = Data("""
            { "error": { "code": 400, "status": "INVALID_ARGUMENT", "details": [ { "reason": "SOMETHING_ELSE" } ] } }
            """.utf8)
        #expect(GeminiDetectionService.error(forStatusCode: 400, body: body) == .invalidResponse)
        #expect(GeminiDetectionService.error(forStatusCode: 400, body: Data("not json".utf8)) == .invalidResponse)
    }

}

/// End-to-end through a real URLSession (stubbed transport). Serialized
/// because the URLProtocol stub's handler is shared global state. Retry
/// tests inject a recording sleep, so nothing here waits in real time.
@Suite(.serialized)
struct GeminiTransportTests {

    private func makeService(recorder: SleepRecorder? = nil) -> GeminiDetectionService {
        GeminiDetectionService(
            apiKey: "TEST-KEY-NOT-REAL",
            session: StubURLProtocol.makeSession(),
            sleep: { duration in await recorder?.record(duration) }
        )
    }

    // MARK: - Detection retry behavior

    @Test func successOnFirstAttemptMakesExactlyOneRequest() async throws {
        StubURLProtocol.reset { _, _ in (200, Fixture.twoObjects, [:]) }

        let objects = try await makeService().detectObjects(in: Data([0x01]))
        #expect(objects.count == 2)
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test func unauthorizedDoesNotRetry() async {
        StubURLProtocol.reset { _, _ in (401, Data(), [:]) }

        await #expect(throws: DetectionError.unauthorized) {
            _ = try await makeService().detectObjects(in: Data([0x01]))
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test func invalidAPIKey400DoesNotRetry() async {
        let body = Data(#"{"error": {"details": [{"reason": "API_KEY_INVALID"}]}}"#.utf8)
        StubURLProtocol.reset { _, _ in (400, body, [:]) }

        await #expect(throws: DetectionError.unauthorized) {
            _ = try await makeService().detectObjects(in: Data([0x01]))
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test func decodingFailureDoesNotRetryAutomatically() async {
        // HTTP success with unusable output is not a transport problem;
        // resending the same bytes would just repeat it.
        StubURLProtocol.reset { _, _ in (200, Data("not an envelope".utf8), [:]) }

        await #expect(throws: DetectionError.decoding) {
            _ = try await makeService().detectObjects(in: Data([0x01]))
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test func transient503SucceedsOnSecondAttempt() async throws {
        let recorder = SleepRecorder()
        StubURLProtocol.reset { _, attempt in
            attempt == 1 ? (503, Data(), [:]) : (200, Fixture.twoObjects, [:])
        }

        let objects = try await makeService(recorder: recorder).detectObjects(in: Data([0x01]))
        #expect(objects.count == 2)
        #expect(StubURLProtocol.requestCount == 2)
        #expect(await recorder.durations == [.seconds(1)])
    }

    @Test func transientFailuresSucceedOnFinalAllowedAttempt() async throws {
        let recorder = SleepRecorder()
        StubURLProtocol.reset { _, attempt in
            attempt < 3 ? (502, Data(), [:]) : (200, Fixture.twoObjects, [:])
        }

        let objects = try await makeService(recorder: recorder).detectObjects(in: Data([0x01]))
        #expect(objects.count == 2)
        #expect(StubURLProtocol.requestCount == 3)
        // Exponential progression: 1 s before retry 1, 2 s before retry 2.
        #expect(await recorder.durations == [.seconds(1), .seconds(2)])
    }

    @Test func rateLimitExhaustsBoundedRetriesThenThrows() async {
        let recorder = SleepRecorder()
        StubURLProtocol.reset { _, _ in (429, Data(), [:]) }

        await #expect(throws: DetectionError.rateLimited) {
            _ = try await makeService(recorder: recorder).detectObjects(in: Data([0x01]))
        }
        #expect(StubURLProtocol.requestCount == GeminiDetectionService.maxAttempts)
        #expect(await recorder.durations.count == GeminiDetectionService.maxAttempts - 1)
    }

    @Test func numericRetryAfterIsPreferredOverBackoff() async throws {
        let recorder = SleepRecorder()
        StubURLProtocol.reset { _, attempt in
            attempt == 1 ? (429, Data(), ["Retry-After": "5"]) : (200, Fixture.twoObjects, [:])
        }

        _ = try await makeService(recorder: recorder).detectObjects(in: Data([0x01]))
        #expect(await recorder.durations == [.seconds(5)])
    }

    @Test func invalidRetryAfterFallsBackToExponentialBackoff() async throws {
        let recorder = SleepRecorder()
        StubURLProtocol.reset { _, attempt in
            attempt == 1 ? (429, Data(), ["Retry-After": "soon"]) : (200, Fixture.twoObjects, [:])
        }

        _ = try await makeService(recorder: recorder).detectObjects(in: Data([0x01]))
        #expect(await recorder.durations == [.seconds(1)])
    }

    @Test func excessiveRetryAfterIsCapped() async throws {
        let recorder = SleepRecorder()
        StubURLProtocol.reset { _, attempt in
            attempt == 1 ? (429, Data(), ["Retry-After": "3600"]) : (200, Fixture.twoObjects, [:])
        }

        _ = try await makeService(recorder: recorder).detectObjects(in: Data([0x01]))
        #expect(await recorder.durations == [GeminiDetectionService.maxRetryDelay])
    }

    @Test func cancellationDuringBackoffPreventsFurtherAttempts() async {
        // Uses the real cancellation-aware sleep: cancelling the task
        // interrupts the backoff and no second request is ever sent.
        StubURLProtocol.reset { _, _ in (503, Data(), [:]) }
        let service = GeminiDetectionService(apiKey: "TEST-KEY-NOT-REAL", session: StubURLProtocol.makeSession())

        let task = Task {
            _ = try await service.detectObjects(in: Data([0x01]))
        }
        // Let the first attempt fail and the (1 s) backoff begin.
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    // MARK: - Connection validation (models.get)

    @Test func validateKeySucceedsOnOKStatus() async throws {
        StubURLProtocol.reset { _, _ in (200, Data("{\"name\": \"models/gemini-3.8-flash\"}".utf8), [:]) }

        try await makeService().validateKey()
    }

    @Test func validateKeyMapsUnauthorized() async {
        StubURLProtocol.reset { _, _ in (403, Data(), [:]) }

        await #expect(throws: DetectionError.unauthorized) {
            try await makeService().validateKey()
        }
    }

    @Test func validateKeyNeverRetries() async {
        // Test Connection is a diagnostic: one tap → one request, even for
        // transient statuses the detection path would retry.
        StubURLProtocol.reset { _, _ in (429, Data(), [:]) }
        await #expect(throws: DetectionError.rateLimited) {
            try await makeService().validateKey()
        }
        #expect(StubURLProtocol.requestCount == 1)

        StubURLProtocol.reset { _, _ in (503, Data(), [:]) }
        await #expect(throws: DetectionError.server(statusCode: 503)) {
            try await makeService().validateKey()
        }
        #expect(StubURLProtocol.requestCount == 1)
    }
}

/// Minimal URLProtocol stub so the real URLSession path is exercised without
/// any network. Not a networking framework — test-only plumbing. The handler
/// receives the 1-based request number so tests can script per-attempt
/// responses; suites using it must be `.serialized` (shared static state).
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Int) -> (Int, Data, [String: String]))?
    nonisolated(unsafe) private(set) static var requestCount = 0

    static func reset(handler: @escaping (URLRequest, Int) -> (Int, Data, [String: String])) {
        requestCount = 0
        self.handler = handler
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = Self.handler else { return }
        Self.requestCount += 1
        let (statusCode, data, headers) = handler(request, Self.requestCount)
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Records backoff sleeps so retry tests never wait in real time.
actor SleepRecorder {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }
}
