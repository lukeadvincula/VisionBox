//
//  GeminiDetectionService.swift
//  VisionBox
//

import Foundation

/// Live object detection backed by the Google Gemini API.
///
/// Sends one stateless Interactions API request (the endpoint family Google
/// currently recommends for new projects) with prepared JPEG data and a
/// structured-output schema, then maps the response into domain models.
///
/// The API key is injected at construction — credential storage belongs to
/// `KeychainService`; this type never reads the Keychain, and the key travels
/// only in the documented `x-goog-api-key` header, never in the URL.
nonisolated struct GeminiDetectionService: ObjectDetectionService {

    /// Current stable GA Flash model (verified against ai.google.dev,
    /// 2026-09-15). A pinned ID keeps portfolio behavior predictable.
    static let model = "gemini-3.8-flash"

    private static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!

    /// The prompt pins Gemini's spatial convention explicitly — the model is
    /// never left to guess the box format.
    static let detectionPrompt = """
        Detect the prominent physical objects in this image. For each object \
        return a short descriptive label (one to four words), an optional \
        general category (such as Electronics, Kitchenware, Furniture, \
        Clothing, Food, Plant, Accessories), and its bounding box. The \
        bounding box must be "box_2d": [ymin, xmin, ymax, xmax], with each \
        coordinate normalized to 0-1000 relative to the image size. Treat \
        each physically separate object as its own entry. Do not include \
        reflections, shadows, or background surfaces such as walls, floors, \
        or countertops.
        """

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        let request = try Self.makeRequest(imageData: imageData, apiKey: apiKey)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // URLSession reports task cancellation as URLError; translate it
            // so callers can treat it like any other Swift cancellation.
            throw CancellationError()
        } catch let error as URLError {
            throw DetectionError.network(error.code)
        } catch {
            throw DetectionError.network(nil)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let error = Self.error(forStatusCode: statusCode) {
            throw error
        }
        return try Self.detections(fromResponseData: data)
    }

    // MARK: - Request construction

    static func makeRequest(imageData: Data, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body = GeminiInteractionRequest(
            model: model,
            input: [
                .image(mimeType: "image/jpeg", base64Data: imageData.base64EncodedString()),
                .text(detectionPrompt),
            ],
            responseFormat: .detectionList
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    // MARK: - Response handling

    /// nil for success statuses; a typed error otherwise.
    static func error(forStatusCode statusCode: Int) -> DetectionError? {
        switch statusCode {
        case 200...299: nil
        case 401, 403: .unauthorized
        case 429: .rateLimited
        case 500...599: .server(statusCode: statusCode)
        default: .invalidResponse
        }
    }

    /// Decodes the interaction envelope, extracts the structured JSON text,
    /// and maps wire detections to domain objects.
    ///
    /// A valid response containing zero objects returns `[]` — that is a
    /// normal outcome, distinct from `.invalidResponse` (no usable output,
    /// e.g. a refusal) and `.decoding` (output that isn't valid detections).
    static func detections(fromResponseData data: Data) throws -> [DetectedObject] {
        let envelope: GeminiInteractionResponse
        do {
            envelope = try JSONDecoder().decode(GeminiInteractionResponse.self, from: data)
        } catch {
            throw DetectionError.decoding
        }

        // Failed interactions and responses with no usable output are treated
        // alike; provider error text is deliberately never surfaced.
        guard envelope.status != "failed",
              let outputText = envelope.outputText else {
            throw DetectionError.invalidResponse
        }

        let wireDetections: [GeminiDetection]
        do {
            wireDetections = try JSONDecoder().decode([GeminiDetection].self, from: Data(outputText.utf8))
        } catch {
            throw DetectionError.decoding
        }
        return wireDetections.compactMap(Self.detectedObject)
    }

    /// Maps one wire detection to the domain, converting Gemini's y-first
    /// 0–1000 box to a normalized top-left-origin `BoundingBox`.
    ///
    /// Malformed or degenerate boxes — wrong coordinate count, reversed
    /// edges, or zero area after clamping to the unit rect — are dropped
    /// rather than rendered as nonsense. IDs are generated locally and are
    /// unique within a result set (stability across calls is not required).
    static func detectedObject(fromWire wire: GeminiDetection) -> DetectedObject? {
        guard wire.box2D.count == 4, !wire.label.isEmpty else { return nil }
        let yMin = wire.box2D[0] / 1000
        let xMin = wire.box2D[1] / 1000
        let yMax = wire.box2D[2] / 1000
        let xMax = wire.box2D[3] / 1000

        let box = BoundingBox(
            x: xMin,
            y: yMin,
            width: xMax - xMin,
            height: yMax - yMin
        ).clamped()
        guard box.area > 0 else { return nil }

        return DetectedObject(
            label: wire.label,
            category: wire.category,
            // The detection API provides no calibrated confidence; nil is
            // honest, and the UI already treats confidence as optional.
            confidence: nil,
            boundingBox: box
        )
    }
}
