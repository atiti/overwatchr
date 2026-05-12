#if os(macOS)
import Foundation
import OverwatchrCore

@MainActor
final class VoiceInteractionController {
    var onStateChange: ((VoiceInteractionDisplayState, String?) -> Void)?

    private let audioCapture: AudioCaptureService
    private let transcriptionProvider: AzureSpeechTranscriptionProvider
    private let insertionService: TextInsertionService
    private let indicatorPanel: VoiceIndicatorPanel
    private let configurationProvider: () throws -> AzureSpeechProviderConfiguration
    private let submitModeProvider: () -> VoiceSubmitMode

    private var activeAudioURL: URL?
    private var isStartingCapture = false
    private var isCapturing = false
    private var shouldFinishAfterStartup = false
    private var transcriptionTask: Task<Void, Never>?

    init(
        audioCapture: AudioCaptureService = AudioCaptureService(),
        transcriptionProvider: AzureSpeechTranscriptionProvider = AzureSpeechTranscriptionProvider(),
        configurationProvider: @escaping () throws -> AzureSpeechProviderConfiguration,
        submitModeProvider: @escaping () -> VoiceSubmitMode
    ) {
        self.audioCapture = audioCapture
        self.transcriptionProvider = transcriptionProvider
        self.insertionService = TextInsertionService()
        self.indicatorPanel = VoiceIndicatorPanel()
        self.configurationProvider = configurationProvider
        self.submitModeProvider = submitModeProvider
    }

    func beginCapture() {
        guard !isStartingCapture, !isCapturing else {
            return
        }

        VoiceDiagnosticLog.write("beginCapture")
        isStartingCapture = true
        shouldFinishAfterStartup = false
        transcriptionTask?.cancel()
        transcriptionTask = Task { @MainActor in
            do {
                _ = try configurationProvider()
                activeAudioURL = try await audioCapture.start()
                isStartingCapture = false
                isCapturing = true
                VoiceDiagnosticLog.write("captureStarted")
                update(.listening, message: "Listening")
                if shouldFinishAfterStartup {
                    VoiceDiagnosticLog.write("finishDeferredDuringStartup")
                    shouldFinishAfterStartup = false
                    finishCapture()
                }
            } catch {
                isStartingCapture = false
                shouldFinishAfterStartup = false
                VoiceDiagnosticLog.write("beginCaptureFailed error=\(type(of: error)) message=\(error.localizedDescription)")
                update(.failed(error.localizedDescription), message: error.localizedDescription)
                indicatorPanel.hide(after: 1.5)
            }
        }
    }

    func finishCapture() {
        guard !isStartingCapture else {
            shouldFinishAfterStartup = true
            return
        }

        guard isCapturing else {
            return
        }

        isCapturing = false
        let audioURL: URL
        do {
            audioURL = try audioCapture.stop()
            let size = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber)?.int64Value ?? -1
            VoiceDiagnosticLog.write("captureStopped bytes=\(size)")
        } catch {
            VoiceDiagnosticLog.write("captureStopFailed error=\(type(of: error)) message=\(error.localizedDescription)")
            update(.failed(error.localizedDescription), message: error.localizedDescription)
            indicatorPanel.hide(after: 1.5)
            return
        }

        update(.processing, message: "Transcribing voice input")
        transcriptionTask = Task { @MainActor in
            defer {
                try? FileManager.default.removeItem(at: audioURL)
                activeAudioURL = nil
            }

            do {
                let configuration = try configurationProvider()
                VoiceDiagnosticLog.write(
                    "transcribeStart region=\(configuration.region) endpointHost=\(configuration.coreConfiguration.endpointHostForDiagnostics ?? "none") language=\(configuration.language)"
                )
                let transcription = try await transcriptionProvider.transcribe(
                    audioFile: audioURL,
                    configuration: configuration
                )
                let confidence = transcription.confidence.map { String($0) } ?? "none"
                VoiceDiagnosticLog.write("transcribeSuccess textLength=\(transcription.text.count) confidence=\(confidence)")
                let command = VoiceCommandParser.parse(
                    transcription.text,
                    submitMode: submitModeProvider()
                )
                guard !command.insertionText.isEmpty else {
                    throw AzureSpeechTranscriptionError.emptyTranscript
                }

                try await insertionService.insert(command.insertionText, submit: command.shouldSubmit)
                VoiceDiagnosticLog.write("insertSuccess submit=\(command.shouldSubmit) textLength=\(command.insertionText.count)")
                update(.inserted, message: command.shouldSubmit ? "Inserted and submitted voice text." : "Inserted voice text.")
                indicatorPanel.hide(after: 1.0)
            } catch {
                VoiceDiagnosticLog.write("voiceFailed error=\(type(of: error)) message=\(error.localizedDescription)")
                update(.failed(error.localizedDescription), message: userFacingMessage(for: error))
                indicatorPanel.hide(after: 2.0)
            }
        }
    }

    func cancel() {
        VoiceDiagnosticLog.write("cancel")
        transcriptionTask?.cancel()
        transcriptionTask = nil
        audioCapture.cancel()
        isStartingCapture = false
        isCapturing = false
        shouldFinishAfterStartup = false
        activeAudioURL = nil
        update(.idle, message: nil)
    }

    private func update(_ state: VoiceInteractionDisplayState, message: String?) {
        if state == .idle {
            indicatorPanel.hide()
        } else {
            indicatorPanel.show(state: state)
        }
        onStateChange?(state, message)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let insertionError = error as? TextInsertionError,
           insertionError == .accessibilityPermissionRequired {
            return "Transcribed voice, but Accessibility access is required to paste it."
        }
        return error.localizedDescription
    }
}
#endif
