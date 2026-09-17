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
        // The schema requests exactly what VisionBox consumes — no category.
        let properties = try #require(items["properties"] as? [String: Any])
        #expect(properties.keys.sorted() == ["box_2d", "label"])
    }

    private func prompt(from request: URLRequest) throws -> String {
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try #require(json["input"] as? [[String: Any]])
        return try #require(input.first { $0["type"] as? String == "text" }?["text"] as? String)
    }

    @Test(arguments: [DetectionDetail.generic, .detailed])
    func promptPinsTheCoordinateConventionInBothModes(detail: DetectionDetail) throws {
        let request = try GeminiDetectionService.makeRequest(
            imageData: Data([0x01]),
            apiKey: apiKey,
            detail: detail
        )
        let prompt = try prompt(from: request)

        // The detection task and spatial convention are mode-independent.
        #expect(prompt.contains("box_2d"))
        #expect(prompt.contains("[ymin, xmin, ymax, xmax]"))
        #expect(prompt.contains("0-1000"))
        #expect(prompt.contains("Detect the prominent physical objects"))
        // Results carry no category metadata; neither mode may request it.
        #expect(!prompt.lowercased().contains("categor"))
    }

    @Test func standardModeAsksForGeneralNamesAndIsTheDefault() throws {
        let standard = try GeminiDetectionService.makeRequest(
            imageData: Data([0x01]),
            apiKey: apiKey,
            detail: .generic
        )
        let standardPrompt = try prompt(from: standard)
        #expect(standardPrompt.contains("general product or object name"))
        #expect(!standardPrompt.contains("brand"))

        // Omitting the parameter behaves exactly like Standard.
        let defaulted = try GeminiDetectionService.makeRequest(imageData: Data([0x01]), apiKey: apiKey)
        #expect(try prompt(from: defaulted) == standardPrompt)
    }

    @Test func detailedModeRequestsEvidenceBackedSpecificity() throws {
        let request = try GeminiDetectionService.makeRequest(
            imageData: Data([0x01]),
            apiKey: apiKey,
            detail: .detailed
        )
        let detailedPrompt = try prompt(from: request)

        // Asks for specificity…
        #expect(detailedPrompt.contains("brand"))
        #expect(detailedPrompt.contains("model"))
        // …but explicitly forbids unsupported guessing.
        #expect(detailedPrompt.contains("Never guess or invent"))
        #expect(detailedPrompt.contains("fall back to the more general name"))
    }

    @Test func bothModesShareTheSameResponseSchema() throws {
        func responseFormat(for detail: DetectionDetail) throws -> NSDictionary {
            let request = try GeminiDetectionService.makeRequest(
                imageData: Data([0x01]),
                apiKey: apiKey,
                detail: detail
            )
            let body = try #require(request.httpBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try #require(json["response_format"] as? NSDictionary)
        }

        // Detection Detail changes only the prompt — never the schema.
        #expect(try responseFormat(for: .generic) == responseFormat(for: .detailed))
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
