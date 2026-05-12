import Foundation

public struct AzureSpeechConfiguration: Equatable, Sendable {
    public let region: String
    public let endpoint: String?
    public let language: String

    public init(region: String, endpoint: String?, language: String) {
        self.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "en-US"
    }

    public var endpointHostForDiagnostics: String? {
        endpoint.flatMap { URL(string: $0)?.host }
    }

    public var languageCandidates: [String] {
        let normalized = language
            .replacingOccurrences(of: "auto:", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: ";", with: ",")

        let candidates = normalized
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, language in
                if !result.contains(language) {
                    result.append(language)
                }
            }

        return candidates.isEmpty ? ["en-US"] : candidates
    }
}

public enum AzureSpeechTranscriptionError: Error, Equatable, LocalizedError {
    case missingRegionOrEndpoint
    case invalidEndpoint(String)
    case invalidResponse
    case recognitionFailed(String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .missingRegionOrEndpoint:
            return "Azure Speech needs a region or endpoint."
        case .invalidEndpoint(let endpoint):
            return "Azure Speech endpoint is invalid: \(endpoint)"
        case .invalidResponse:
            return "Azure Speech returned an unreadable response."
        case .recognitionFailed(let status):
            return "Azure Speech recognition failed: \(status)"
        case .emptyTranscript:
            return "Azure Speech returned an empty transcript."
        }
    }
}

public enum AzureSpeechShortAudioRequest {
    public static func url(for configuration: AzureSpeechConfiguration) throws -> URL {
        let baseURL: URL
        if let endpoint = configuration.endpoint {
            guard let parsed = URL(string: endpoint) else {
                throw AzureSpeechTranscriptionError.invalidEndpoint(endpoint)
            }
            baseURL = normalizedSpeechEndpoint(parsed, fallbackRegion: configuration.region)
        } else {
            guard !configuration.region.isEmpty else {
                throw AzureSpeechTranscriptionError.missingRegionOrEndpoint
            }
            guard let parsed = URL(string: "https://\(configuration.region).stt.speech.microsoft.com") else {
                throw AzureSpeechTranscriptionError.invalidEndpoint(configuration.region)
            }
            baseURL = parsed
        }

        let recognitionURL = baseURL
            .appendingPathComponent("speech")
            .appendingPathComponent("recognition")
            .appendingPathComponent("conversation")
            .appendingPathComponent("cognitiveservices")
            .appendingPathComponent("v1")

        guard var components = URLComponents(url: recognitionURL, resolvingAgainstBaseURL: false) else {
            throw AzureSpeechTranscriptionError.invalidEndpoint(baseURL.absoluteString)
        }
        components.queryItems = [
            URLQueryItem(name: "language", value: configuration.languageCandidates.first ?? "en-US"),
            URLQueryItem(name: "format", value: "detailed")
        ]

        guard let url = components.url else {
            throw AzureSpeechTranscriptionError.invalidEndpoint(baseURL.absoluteString)
        }
        return url
    }

    private static func normalizedSpeechEndpoint(_ endpoint: URL, fallbackRegion: String) -> URL {
        guard let host = endpoint.host?.lowercased(),
              host.hasSuffix(".api.cognitive.microsoft.com") else {
            return endpoint
        }

        let region = host
            .replacingOccurrences(of: ".api.cognitive.microsoft.com", with: "")
            .nonEmpty ?? fallbackRegion.nonEmpty
        guard let region,
              let normalized = URL(string: "https://\(region).stt.speech.microsoft.com") else {
            return endpoint
        }
        return normalized
    }
}

public enum AzureSpeechShortAudioResponse {
    public static func parse(_ data: Data) throws -> VoiceTranscriptionResult {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.recognitionStatus == "Success" else {
            throw AzureSpeechTranscriptionError.recognitionFailed(response.recognitionStatus)
        }

        let best = response.nBest?.first
        let text = response.displayText?.nonEmpty ?? best?.display?.nonEmpty
        guard let text else {
            throw AzureSpeechTranscriptionError.emptyTranscript
        }

        return VoiceTranscriptionResult(
            text: text,
            provider: "azureSpeech",
            confidence: best?.confidence
        )
    }

    private struct Response: Decodable {
        let recognitionStatus: String
        let displayText: String?
        let nBest: [Best]?

        enum CodingKeys: String, CodingKey {
            case recognitionStatus = "RecognitionStatus"
            case displayText = "DisplayText"
            case nBest = "NBest"
        }
    }

    private struct Best: Decodable {
        let display: String?
        let confidence: Double?

        enum CodingKeys: String, CodingKey {
            case display = "Display"
            case confidence = "Confidence"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
