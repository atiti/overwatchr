import CryptoKit
import XCTest
@testable import OverwatchrCore

final class ZellijFocusTests: XCTestCase {
    func testLegacyEventsStillDecode() throws {
        let data = Data(#"{"agent_id":"codex-old","status":"needs_input","timestamp":1}"#.utf8)
        let event = try JSONDecoder().decode(AgentEvent.self, from: data)
        XCTAssertNil(event.zellijSession)
        XCTAssertNil(event.zellijPaneID)
    }

    func testStandaloneHookCarriesZellijPaneAddress() {
        let input = HookBridgeInput(tool: .codex, payload: ["session_id": .string("standalone")],
                                    environment: ["ZELLIJ_SESSION_NAME": "work", "ZELLIJ_PANE_ID": "7",
                                                  "TERM_PROGRAM": "ghostty", "OVERWATCHR_TTY": "/dev/ttys055"])
        guard case .emit(let event) = HookBridge.action(for: input) else { return XCTFail("Missing alert") }
        XCTAssertEqual(event.zellijSession, "work")
        XCTAssertEqual(event.zellijPaneID, 7)
        XCTAssertNil(event.tty, "An inner pane TTY must not be used to target the outer terminal")
    }

    func testSharedOwnerHookResolvesRegisteredTerminalView() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex").standardizedFileURL.resolvingSymlinksInPath().path
        let hash = SHA256.hash(data: Data(codex.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
        let id = "01a16cea-b69e-7772-b0c2-77d9a04435c0"
        let file = root.appendingPathComponent("shared-server/\(hash)/zellij-targets/\(id).json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target: [String: Any] = ["session": "agentroute", "pane_id": 9, "terminal": "ghostty",
                                     "tty": "/dev/ttys012", "thread": id]
        try JSONSerialization.data(withJSONObject: target).write(to: file)
        let input = HookBridgeInput(tool: .codex, payload: ["session_id": .string(id)],
                                    environment: ["AGENTROUTE_HOME": root.path, "CODEX_HOME": codex])
        guard case .emit(let event) = HookBridge.action(for: input) else { return XCTFail("Missing alert") }
        XCTAssertEqual(event.zellijSession, "agentroute")
        XCTAssertEqual(event.zellijPaneID, 9)
        XCTAssertEqual(event.zellijThreadID, id)
        XCTAssertEqual(event.terminal, "ghostty")
        XCTAssertEqual(event.tty, "/dev/ttys012")
        let decoded = try JSONDecoder().decode(AgentEvent.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(event, decoded)
    }

    func testFocusUsesArgumentsWithoutShellInterpolation() {
        XCTAssertEqual(ZellijFocus.arguments(session: "work $(anything)", paneID: 3),
                       ["--session", "work $(anything)", "action", "focus-pane-id", "terminal_3"])
    }

    func testAnotherPaneIsNotAcknowledgedBySharedOuterTTY() {
        let event = AgentEvent(agentID: "codex-chat", status: .needsInput, terminal: "ghostty",
                               tty: "/dev/ttys012", zellijSession: "work", zellijPaneID: 3)
        let context = FrontmostSessionContext(terminalName: "ghostty", ttyPath: "/dev/ttys012")
        XCTAssertFalse(FrontmostSessionMatcher.matches(event: event, context: context))
    }
}
