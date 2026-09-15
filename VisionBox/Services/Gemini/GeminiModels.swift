//
//  GeminiModels.swift
//  VisionBox
//

import Foundation

// Wire types for the Gemini Interactions API
// (POST https://generativelanguage.googleapis.com/v1beta/interactions).
//
// These types exist only inside the Gemini integration: nothing outside
// `GeminiDetectionService` sees `box_2d` or the response envelope — mapping
// to domain models happens immediately on decode.

// MARK: - Request

nonisolated struct GeminiInteractionRequest: Encodable {
    let model: String
    /// Stateless mode: VisionBox has no use for server-side interaction
    /// storage, and user photos shouldn't be retained by default.
    let store = false
    let input: [InputPart]
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, store, input
        case responseFormat = "response_format"
    }

    struct InputPart: Encodable {
        let type: String
        var text: String?
        var mimeType: String?
        var data: String?

        enum CodingKeys: String, CodingKey {
            case type, text, data
            case mimeType = "mime_type"
        }

        static func text(_ text: String) -> InputPart {
            InputPart(type: "text", text: text, mimeType: nil, data: nil)
        }

        static func image(mimeType: String, base64Data: String) -> InputPart {
            InputPart(type: "image", text: nil, mimeType: mimeType, data: base64Data)
        }
    }

    /// Structured output: JSON constrained by a schema.
    struct ResponseFormat: Encodable {
        let type = "text"
        let mimeType = "application/json"
        let schema: DetectionListSchema

        enum CodingKeys: String, CodingKey {
            case type, schema
            case mimeType = "mime_type"
        }

        static let detectionList = ResponseFormat(schema: DetectionListSchema())
    }

    /// JSON Schema for the detection list: an array of
    /// `{label, box_2d[, category]}` objects.
    struct DetectionListSchema: Encodable {
        let type = "array"
        let items = Items()

        struct Items: Encodable {
            let type = "object"
            let properties = Properties()
            let required = ["label", "box_2d"]

            struct Properties: Encodable {
                let label = StringProperty()
                let category = StringProperty()
                let box2D = BoxProperty()

                enum CodingKeys: String, CodingKey {
                    case label, category
                    case box2D = "box_2d"
                }
            }
        }

        struct StringProperty: Encodable {
            let type = "string"
        }

        struct BoxProperty: Encodable {
            let type = "array"
            let items = IntegerProperty()

            struct IntegerProperty: Encodable {
                let type = "integer"
            }
        }
    }
}

// MARK: - Response

nonisolated struct GeminiInteractionResponse: Decodable {
    let status: String?
    let steps: [Step]?

    struct Step: Decodable {
        let type: String?
        let content: [ContentItem]?

        struct ContentItem: Decodable {
            let type: String?
            let text: String?
        }
    }

    /// The model's final text output. Prefers `model_output` steps and takes
    /// the last one, tolerating extra step kinds the API may add.
    var outputText: String? {
        guard let steps else { return nil }
        let modelOutputSteps = steps.filter { $0.type == "model_output" }
        for step in (modelOutputSteps.isEmpty ? steps : modelOutputSteps).reversed() {
            if let text = step.content?.first(where: { $0.text != nil })?.text {
                return text
            }
        }
        return nil
    }
}

/// One detection as Gemini reports it: `box_2d` is `[ymin, xmin, ymax, xmax]`
/// normalized to 0–1000. This convention never leaves the Gemini layer.
nonisolated struct GeminiDetection: Decodable {
    let label: String
    let category: String?
    let box2D: [Double]

    enum CodingKeys: String, CodingKey {
        case label, category
        case box2D = "box_2d"
    }
}
