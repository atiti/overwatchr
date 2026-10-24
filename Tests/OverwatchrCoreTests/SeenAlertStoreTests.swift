import XCTest
@testable import OverwatchrCore

final class SeenAlertStoreTests: XCTestCase {
    func testRoundTripsLedger() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("seen.json")
        let store = SeenAlertStore(fileURL: fileURL)
        var ledger = SeenAlertLedger()

        ledger.markSeen(AgentEvent(agentID: "copy", project: "landing", status: .needsInput, timestamp: 123))

        try store.save(ledger)
        let loaded = try store.load()

        XCTAssertEqual(loaded, ledger)
    }

    func testSaveCreatesFileWithOwnerOnlyPermissions() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("seen.json")
        let store = SeenAlertStore(fileURL: fileURL)

        try store.save(SeenAlertLedger())

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }
}
