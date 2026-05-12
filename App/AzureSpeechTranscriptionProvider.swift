#if os(macOS)
import Foundation
import OverwatchrCore

struct AzureSpeechProviderConfiguration: Sendable {
    let key: String
    let region: String
    let endpoint: String?
    let language: String

    var coreConfiguration: AzureSpeechConfiguration {
        AzureSpeechConfiguration(region: region, endpoint: endpoint, language: language)
    }
}

enum AzureSpeechProviderError: Error, LocalizedError {
    case missingKey
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Azure Speech key is missing."
        case .requestFailed(let statusCode, let body):
            if body.isEmpty {
                return "Azure Speech request failed with HTTP \(statusCode)."
            }
            return "Azure Speech request failed with HTTP \(statusCode): \(body)"
        }
    }
}

struct AzureSpeechTranscriptionProvider {
    func transcribe(audioFile: URL, configuration: AzureSpeechProviderConfiguration) async throws -> VoiceTranscriptionResult {
        let key = configuration.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw AzureSpeechProviderError.missingKey
        }

        let candidates = configuration.coreConfiguration.languageCandidates
        if candidates.count > 1 {
            return try await transcribeWithCandidates(
                candidates,
                audioFile: audioFile,
                configuration: configuration,
                key: key
            )
        }

        return try await transcribe(
            audioFile: audioFile,
            configuration: configuration,
            key: key,
            language: candidates.first ?? configuration.language
        )
    }

    private func transcribeWithCandidates(
        _ candidates: [String],
        audioFile: URL,
        configuration: AzureSpeechProviderConfiguration,
        key: String
    ) async throws -> VoiceTranscriptionResult {
        VoiceDiagnosticLog.write("azureLanguageCandidates=\(candidates.joined(separator: ","))")

        var results: [VoiceTranscriptionResult] = []
        var lastError: Error?

        await withThrowingTaskGroup(of: VoiceTranscriptionResult.self) { group in
            for language in candidates {
                group.addTask {
                    try await transcribe(
                        audioFile: audioFile,
                        configuration: configuration,
                        key: key,
                        language: language
                    )
                }
            }

            while let result = await group.nextResult() {
                switch result {
                case .success(let transcription):
                    results.append(transcription)
                case .failure(let error):
                    lastError = error
                }
            }
        }

        if let best = results.max(by: { lhs, rhs in
            (lhs.confidence ?? 0) < (rhs.confidence ?? 0)
        }) {
            VoiceDiagnosticLog.write("azureLanguageSelected provider=\(best.provider) confidence=\(best.confidence.map { String($0) } ?? "none")")
            return best
        }

        if let lastError {
            throw lastError
        }
        throw AzureSpeechTranscriptionError.emptyTranscript
    }

    private func transcribe(
        audioFile: URL,
        configuration: AzureSpeechProviderConfiguration,
        key: String,
        language: String
    ) async throws -> VoiceTranscriptionResult {
        let coreConfiguration = AzureSpeechConfiguration(
            region: configuration.region,
            endpoint: configuration.endpoint,
            language: language
        )
        let url = try AzureSpeechShortAudioRequest.url(for: coreConfiguration)
        VoiceDiagnosticLog.write("azureRequest host=\(url.host ?? "unknown") path=\(url.path) language=\(language)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let audioData = try Data(contentsOf: audioFile)
        let (data, response) = try await URLSession.shared.upload(for: request, from: audioData)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        VoiceDiagnosticLog.write("azureResponse status=\(statusCode) bytes=\(data.count)")
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AzureSpeechProviderError.requestFailed(statusCode, body)
        }

        let result = try AzureSpeechShortAudioResponse.parse(data)
        return VoiceTranscriptionResult(
            text: result.text,
            provider: "azureSpeech:\(language)",
            confidence: result.confidence
        )
    }
}
#endif
