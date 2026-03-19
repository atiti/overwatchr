import Foundation

public struct SeenAlertStore: Sendable {
    public static let defaultFileURL = EventStore.defaultDirectoryURL.appendingPathComponent("seen.json")

    public let fileURL: URL

    public init(fileURL: URL = SeenAlertStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public func load() throws -> SeenAlertLedger {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return SeenAlertLedger()
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return SeenAlertLedger()
        }

        return try JSONDecoder().decode(SeenAlertLedger.self, from: data)
    }

    public func save(_ ledger: SeenAlertLedger) throws {
        try ensureStorageDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ledger)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureStorageDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
