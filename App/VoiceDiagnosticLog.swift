#if os(macOS)
import Foundation

struct VoiceDiagnosticLog {
    private static let maxLineLength = 900

    static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
            .prefix(maxLineLength)
            .appending("\n")

        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".overwatchr", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("voice.log")
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try data.write(to: fileURL)
            }
        } catch {
            // Diagnostics must never break voice input.
        }
    }
}
#endif
