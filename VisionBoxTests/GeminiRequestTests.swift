//
//  GeminiRequestTests.swift
//  VisionBoxTests
//

import Foundation
import Testing
@testable import VisionBox

struct GeminiRequestTests {

    private let apiKey = "TEST-KEY-NOT-REAL"

    @Test func requestUsesDocumentedEndpointAndAuthHeader() throws {
        let request = try GeminiDetectionService.makeRequest(imageData: Data([0x01]), apiKey: apiKey)

        #expect(request.httpMethod == "POST")
        let url = try #require(request.url)
        #expect(url.host() == "generativelanguage.googleapis.com")
        #expect(url.path() == "/v1beta/interactions")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == apiKey)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func apiKeyNeverAppearsInTheURL() throws {
        let request = try GeminiDetectionService.makeRequest(imageData: Data([0x01]), apiKey: apiKey)
        let url = try #require(request.url)
        #expect(url.query() == nil)
        #expect(!url.absoluteString.contains(apiKey))
    }

    @Test func bodyCarriesModelImagePromptAndSchema() throws {
        let imageData = Data("fake-jpeg-bytes".utf8)
        let request = try GeminiDetectionService.makeRequest(imageData: imageData, apiKey: apiKey)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["model"] as? String == "gemini-3.8-flash")
        #expect(json["store"] as? Bool == false)

        let input = try #require(json["input"] as? [[String: Any]])
        let imagePart = try #require(input.first { $0["type"] as? String == "image" })
        #expect(imagePart["mime_type"] as? String == "image/jpeg")
        #expect(imagePart["data"] as? String == imageData.base64EncodedString())

        let responseFormat = try #require(json["response_format"] as? [String: Any])
        #expect(responseFormat["mime_type"] as? String == "application/json")
        let schema = try #require(responseFormat["schema"] as? [String: Any])
        #expect(schema["type"] as? String == "array")
        let items = try #require(schema["items"] as? [String: Any])
        #expect((items["required"] as? [String])?.sorted() == ["box_2d", "label"])
    }

    @Test func promptPinsTheCoordinateConvention() throws {
        let request = try GeminiDetectionService.makeRequest(imageData: Data([0x01]), apiKey: apiKey)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try #require(json["input"] as? [[String: Any]])
        let prompt = try #require(input.first { $0["type"] as? String == "text" }?["text"] as? String)

        #expect(prompt.contains("box_2d"))
        #expect(prompt.contains("[ymin, xmin, ymax, xmax]"))
        #expect(prompt.contains("0-1000"))
    }

    @Test func apiKeyNeverAppearsInTheBody() throws {
        let request = try GeminiDetectionService.makeRequest(imageData: Data([0x01]), apiKey: apiKey)
        let body = try #require(request.httpBody)
        #expect(!String(decoding: body, as: UTF8.self).contains(apiKey))
    }

    // MARK: - Connection validation (models.get)

    @Test func validationRequestIsAMinimalAuthenticatedGET() throws {
        let request = GeminiDetectionService.makeValidationRequest(apiKey: apiKey)

        #expect(request.httpMethod == "GET")
        let url = try #require(request.url)
        #expect(url.host() == "generativelanguage.googleapis.com")
        #expect(url.path() == "/v1beta/models/gemini-3.8-flash")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == apiKey)
    }

    @Test func requestsCarryExplicitTimeouts() throws {
        let detection = try GeminiDetectionService.makeRequest(imageData: Data([0x01]), apiKey: apiKey)
        #expect(detection.timeoutInterval == GeminiDetectionService.detectionTimeout)

        let validation = GeminiDetectionService.makeValidationRequest(apiKey: apiKey)
        #expect(validation.timeoutInterval == GeminiDetectionService.validationTimeout)
    }

    @Test func validationRequestCarriesNoBodyAndNoKeyInURL() throws {
        let request = GeminiDetectionService.makeValidationRequest(apiKey: apiKey)

        // No body at all: no image, no personal data, no key.
        #expect(request.httpBody == nil)
        let url = try #require(request.url)
        #expect(url.query() == nil)
        #expect(!url.absoluteString.contains(apiKey))
    }
}
