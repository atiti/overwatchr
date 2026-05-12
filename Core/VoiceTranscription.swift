import Foundation

public struct VoiceTranscriptionResult: Equatable, Sendable {
    public let text: String
    public let provider: String
    public let confidence: Double?

    public init(text: String, provider: String, confidence: Double? = nil) {
        self.text = text
        self.provider = provider
        self.confidence = confidence
    }
}

public struct VoiceTranscriptionOptions: Equatable, Sendable {
    public let language: String

    public init(language: String = "en-US") {
        self.language = language
    }
}

public enum VoiceTranscriptionEvent: Equatable, Sendable {
    case partial(String)
    case final(VoiceTranscriptionResult)
}
