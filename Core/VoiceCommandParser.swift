import Foundation

public enum VoiceSubmitMode: String, Codable, Sendable, CaseIterable {
    case disabled
    case stripAndSubmit
    case keepAndSubmit
}

public struct VoiceCommandResult: Equatable, Sendable {
    public let insertionText: String
    public let shouldSubmit: Bool

    public init(insertionText: String, shouldSubmit: Bool) {
        self.insertionText = insertionText
        self.shouldSubmit = shouldSubmit
    }
}

public enum VoiceCommandParser {
    private static let submitPhrases = [
        "press enter",
        "hit enter",
        "send it",
        "submit"
    ]

    public static func parse(_ transcript: String, submitMode: VoiceSubmitMode) -> VoiceCommandResult {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard submitMode != .disabled else {
            return VoiceCommandResult(insertionText: trimmed, shouldSubmit: false)
        }

        let normalizedTranscript = normalized(trimmed)
        guard let phrase = submitPhrases.first(where: { normalizedTranscript.hasSuffix($0) }) else {
            return VoiceCommandResult(insertionText: trimmed, shouldSubmit: false)
        }

        let insertionText = removingTerminalPhrase(phrase, from: trimmed)
        guard !insertionText.isEmpty else {
            return VoiceCommandResult(insertionText: trimmed, shouldSubmit: false)
        }

        switch submitMode {
        case .disabled:
            return VoiceCommandResult(insertionText: trimmed, shouldSubmit: false)
        case .stripAndSubmit:
            return VoiceCommandResult(insertionText: insertionText, shouldSubmit: true)
        case .keepAndSubmit:
            return VoiceCommandResult(insertionText: trimmed, shouldSubmit: true)
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }

    private static func removingTerminalPhrase(_ phrase: String, from transcript: String) -> String {
        var wordsToRemove = phrase.split(separator: " ").count
        var keptWords: [Substring] = []

        for word in transcript.split(separator: " ").reversed() {
            if wordsToRemove > 0 {
                wordsToRemove -= 1
            } else {
                keptWords.append(word)
            }
        }

        return keptWords
            .reversed()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
    }
}
