import CryptoKit
import Foundation

public struct ZellijTarget: Codable, Equatable, Sendable {
    public let session: String
    public let paneID: Int
    public let terminal: String?
    public let tty: String?
    public let thread: String?

    enum CodingKeys: String, CodingKey {
        case session, terminal, tty, thread
        case paneID = "pane_id"
    }

    public static func resolve(environment: [String: String], agentID: String) -> ZellijTarget? {
        if let session = environment["ZELLIJ_SESSION_NAME"], !session.isEmpty,
           let rawID = environment["ZELLIJ_PANE_ID"], let paneID = Int(rawID), paneID >= 0 {
            // OVERWATCHR_TTY is an inner pane TTY; leave it out of the outer
            // terminal match. AgentRoute's saved host context is more precise.
            return ZellijTarget(session: session, paneID: paneID, terminal: nil, tty: nil, thread: nil)
        }
        guard agentID.hasPrefix("codex-"),
              let uuid = UUID(uuidString: String(agentID.dropFirst(6))) else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexHome = URL(fileURLWithPath: environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path)
            .standardizedFileURL.resolvingSymlinksInPath().path
        let identity = SHA256.hash(data: Data(codexHome.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
        let routeHome = URL(fileURLWithPath: environment["AGENTROUTE_HOME"] ?? home.appendingPathComponent(".agentroute").path)
        let url = routeHome.appendingPathComponent("shared-server/\(identity)/zellij-targets/\(uuid.uuidString.lowercased()).json")
        guard let data = try? Data(contentsOf: url),
              let target = try? JSONDecoder().decode(ZellijTarget.self, from: data),
              !target.session.isEmpty, target.paneID >= 0 else { return nil }
        return target
    }
}

public enum ZellijFocus {
    public static func arguments(session: String, paneID: Int) -> [String] {
        ["--session", session, "action", "focus-pane-id", "terminal_\(paneID)"]
    }

    public static func focus(event: AgentEvent) throws {
        guard let session = event.zellijSession, let paneID = event.zellijPaneID, paneID >= 0 else {
            throw FocusError.activationFailed("The Zellij alert has no valid pane address.")
        }
        let environment = ProcessInfo.processInfo.environment
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        guard let binary = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent("zellij") })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw FocusError.activationFailed("Zellij is not installed or cannot be found.")
        }
        let output = try run(binary, ["--session", session, "action", "list-panes", "--all", "--json"])
        guard let panes = try JSONSerialization.jsonObject(with: output) as? [[String: Any]],
              let pane = panes.first(where: { ($0["id"] as? Int) == paneID && ($0["is_plugin"] as? Bool) == false }),
              (pane["exited"] as? Bool) != true else {
            throw FocusError.activationFailed("The Zellij pane is no longer running.")
        }
        if let thread = event.zellijThreadID,
           !(pane["terminal_command"] as? String ?? "").contains("zellij client --thread " + thread) {
            throw FocusError.activationFailed("The Zellij pane now belongs to a different chat.")
        }
        _ = try run(binary, arguments(session: session, paneID: paneID))
    }

    private static func run(_ binary: URL, _ arguments: [String]) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        guard completed.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            throw FocusError.activationFailed("Zellij did not respond in time.")
        }
        guard process.terminationStatus == 0 else {
            throw FocusError.activationFailed("Could not focus the Zellij session. Attach with `ar start` first.")
        }
        return try Data(contentsOf: url)
    }
}
