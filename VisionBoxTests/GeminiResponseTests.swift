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

}

/// End-to-end through a real URLSession (stubbed transport). Serialized
/// because the URLProtocol stub's handler is shared global state.
@Suite(.serialized)
struct GeminiTransportTests {

    @Test func fullRequestPathMapsASuccessfulResponse() async throws {
        let service = GeminiDetectionService(apiKey: "TEST-KEY-NOT-REAL", session: StubURLProtocol.makeSession())
        StubURLProtocol.handler = { _ in (200, Fixture.twoObjects) }

        let objects = try await service.detectObjects(in: Data([0x01]))
        #expect(objects.count == 2)
    }

    @Test func fullRequestPathMapsUnauthorizedStatus() async {
        let service = GeminiDetectionService(apiKey: "TEST-KEY-NOT-REAL", session: StubURLProtocol.makeSession())
        StubURLProtocol.handler = { _ in (401, Data()) }

        await #expect(throws: DetectionError.unauthorized) {
            _ = try await service.detectObjects(in: Data([0x01]))
        }
    }
}

/// Minimal URLProtocol stub so the real URLSession path is exercised without
/// any network. Not a networking framework — test-only plumbing.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = Self.handler else { return }
        let (statusCode, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
