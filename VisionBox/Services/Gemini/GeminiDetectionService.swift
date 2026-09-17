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

    /// The base prompt pins the detection task and Gemini's spatial
    /// convention explicitly — the model is never left to guess the box
    /// format. Object detection stays the primary task in both detail modes;
    /// only the identification instruction below varies.
    static let detectionPrompt = """
        Detect the prominent physical objects in this image. For each object \
        return a short descriptive label and its bounding box. The bounding \
        box must be "box_2d": [ymin, xmin, ymax, xmax], with each coordinate \
        normalized to 0-1000 relative to the image size. Treat each \
        physically separate object as its own entry. Do not include \
        reflections, shadows, or background surfaces such as walls, floors, \
        or countertops.
        """

    /// The per-mode identification suffix — one base prompt, two small
    /// variants, never two duplicated prompts.
    static func identificationInstruction(for detail: DetectionDetail) -> String {
        switch detail {
        case .generic:
            """
            Identify each object with a concise, useful general product or \
            object name, such as "Game Controller" or "Power Bank".
            """
        case .detailed:
            """
            Identify each object as specifically as the visible evidence \
            supports: include the brand, product line, model, edition, \
            color, or variant when it is reliably identifiable from logos, \
            printed text, packaging, or distinctive product design — for \
            example "DualSense Wireless Controller" instead of "Game \
            Controller". Never guess or invent details the image does not \
            clearly support; when uncertain, fall back to the more general \
            name.
            """
        }
    }

    static func prompt(for detail: DetectionDetail) -> String {
        detectionPrompt + " " + identificationInstruction(for: detail)
    }

    private let apiKey: String
    /// Fixed per instance: a fresh service is constructed for each analysis
    /// with the preference current at that moment, so automatic retries
    /// inside one analysis always use the same detail level, while the next
    /// user-initiated analysis picks up any Settings change.
    private let detail: DetectionDetail
    private let session: URLSession
    /// Injectable so retry tests don't wait in real time. The production
    /// default is `Task.sleep`, which is cancellation-aware.
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        apiKey: String,
        detail: DetectionDetail = .generic,
        session: URLSession = .shared,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.apiKey = apiKey
        self.detail = detail
        self.session = session
        self.sleep = sleep
    }

    // MARK: - Retry policy (detection requests only)

    /// Bounded retry for transient detection failures: one initial attempt
    /// plus up to two retries. Applies only to `detectObjects` — Test
    /// Connection stays deliberately single-attempt.
    static let maxAttempts = 3
    /// Exponential fallback when no usable Retry-After arrives: 1 s before
    /// the first retry, 2 s before the second.
    static let baseRetryDelay: Duration = .seconds(1)
    /// Ceiling on any automatic wait, including a server-provided
    /// Retry-After — the UI must never sit frozen for minutes on a header's
    /// say-so.
    static let maxRetryDelay: Duration = .seconds(10)

    /// Per-request timeouts: detection uploads an image and waits for
    /// analysis; validation is a tiny metadata GET.
    static let detectionTimeout: TimeInterval = 60
    static let validationTimeout: TimeInterval = 15

    func detectObjects(in imageData: Data) async throws -> [DetectedObject] {
        // Built once, before the retry loop: every automatic retry resends
        // this exact request, detail level included.
        let request = try Self.makeRequest(imageData: imageData, apiKey: apiKey, detail: detail)

        var attempt = 1
        while true {
            do {
                let data = try await send(request)
                // Decode/mapping failures throw plain DetectionError below,
                // which deliberately never retries: HTTP success with
                // unusable output isn't a transient transport problem.
                return try Self.detections(fromResponseData: data)
            } catch let failure as AttemptFailure {
                guard failure.error.isTransient, attempt < Self.maxAttempts else {
                    throw failure.error
                }
                // Cancellation-aware backoff: a cancelled sleep throws, so no
                // further attempt is ever made after cancellation.
                try await sleep(Self.retryDelay(afterAttempt: attempt, retryAfter: failure.retryAfter))
                attempt += 1
            }
        }
    }

    /// Minimal credential/model-access check for Settings' Save & Test and
    /// Test Connection: fetches metadata for the exact model VisionBox uses
    /// (`models.get`). Authenticates the key and confirms model access
    /// without generating anything — no tokens consumed, no image sent.
    /// One tap → one attempt; diagnostics never auto-retry.
    func validateKey() async throws {
        do {
            _ = try await send(Self.makeValidationRequest(apiKey: apiKey))
        } catch let failure as AttemptFailure {
            throw failure.error
        }
    }

    /// One attempt's failure: the classified error plus the server's
    /// Retry-After, kept separate so retry decisions rest on status/header
    /// semantics — never on parsing user-facing strings.
    struct AttemptFailure: Error {
        let error: DetectionError
        let retryAfter: Duration?
    }

    /// One transport attempt: sends the request, translates cancellation and
    /// transport failures, and maps HTTP status codes to typed errors.
    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // URLSession reports task cancellation as URLError; translate it
            // so callers can treat it like any other Swift cancellation.
            throw CancellationError()
        } catch let error as URLError {
            throw AttemptFailure(error: .network(error.code), retryAfter: nil)
        } catch {
            throw AttemptFailure(error: .network(nil), retryAfter: nil)
        }

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        if let error = Self.error(forStatusCode: statusCode, body: data) {
            throw AttemptFailure(error: error, retryAfter: Self.retryAfter(from: httpResponse))
        }
        return data
    }

    /// Numeric Retry-After seconds, if present and valid. The HTTP-date form
    /// is deliberately unsupported: Google documents no Retry-After contract
    /// ("wait and retry after a short period"), so this is opportunistic
    /// standard-HTTP behavior — and the retry loop caps whatever arrives.
    static func retryAfter(from response: HTTPURLResponse?) -> Duration? {
        guard let value = response?.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(value.trimmingCharacters(in: .whitespaces)),
              seconds > 0 else {
            return nil
        }
        return .seconds(seconds)
    }

    /// Delay before the next attempt: a capped server-provided Retry-After
    /// when available, otherwise capped exponential backoff (1 s, 2 s, …).
    static func retryDelay(afterAttempt attempt: Int, retryAfter: Duration?) -> Duration {
        if let retryAfter {
            return min(retryAfter, maxRetryDelay)
        }
        let exponential = baseRetryDelay * (1 << max(attempt - 1, 0))
        return min(exponential, maxRetryDelay)
    }

    // MARK: - Request construction

    static func makeRequest(
        imageData: Data,
        apiKey: String,
        detail: DetectionDetail = .generic
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = detectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body = GeminiInteractionRequest(
            model: model,
            input: [
                .image(mimeType: "image/jpeg", base64Data: imageData.base64EncodedString()),
                .text(prompt(for: detail)),
            ],
            responseFormat: .detectionList
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// `models.get` for the pinned model: a GET with no body — the key
    /// travels in the auth header here too, never in the URL.
    static func makeValidationRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model)")!
        )
        request.timeoutInterval = validationTimeout
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        return request
    }

    // MARK: - Response handling

    /// nil for success statuses; a typed error otherwise.
    ///
    /// Google reports invalid API keys as HTTP 400 with error reason
    /// `API_KEY_INVALID` (observed against the live API, 2026-09-16) rather
    /// than 401/403, so 400 bodies are inspected before falling through.
    static func error(forStatusCode statusCode: Int, body: Data = Data()) -> DetectionError? {
        switch statusCode {
        case 200...299: nil
        case 401, 403: .unauthorized
        case 400 where isInvalidAPIKeyBody(body): .unauthorized
        case 429: .rateLimited
        case 500...599: .server(statusCode: statusCode)
        default: .invalidResponse
        }
    }

    /// Classification only — the error body is never surfaced to the UI.
    static func isInvalidAPIKeyBody(_ body: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: body) else {
            return false
        }
        return envelope.error?.details?.contains { $0.reason == "API_KEY_INVALID" } ?? false
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
            // The detection API provides no calibrated confidence; nil is
            // honest, and the UI already treats confidence as optional.
            confidence: nil,
            boundingBox: box
        )
    }
}
