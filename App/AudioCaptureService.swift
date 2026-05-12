#if os(macOS)
import AVFoundation
import Foundation

enum AudioCaptureError: Error, LocalizedError {
    case microphonePermissionDenied
    case recorderUnavailable
    case notRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required for voice input."
        case .recorderUnavailable:
            return "Could not start microphone recording."
        case .notRecording:
            return "No voice recording is active."
        }
    }
}

final class AudioCaptureService: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    func start() async throws -> URL {
        let authorizationStatus = Self.microphoneAuthorizationStatus()
        VoiceDiagnosticLog.write("microphoneStatus=\(authorizationStatus.rawValue)")
        guard await Self.requestMicrophoneAccess() else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("overwatchr-voice-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioCaptureError.recorderUnavailable
        }

        self.recorder = recorder
        self.outputURL = url
        VoiceDiagnosticLog.write("recorderStarted url=\(url.lastPathComponent)")
        return url
    }

    func stop() throws -> URL {
        guard let recorder, let outputURL else {
            throw AudioCaptureError.notRecording
        }

        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        return outputURL
    }

    func cancel() {
        recorder?.stop()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        recorder = nil
        outputURL = nil
    }

    static func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
#endif
