import XCTest
@testable import OverwatchrCore

final class HerdrFocusTests: XCTestCase {
    private let chat = "01a216c2-c432-78c0-bc38-918d22924a89"

    private func panes(_ entries: [(pane: String, session: String?)]) -> [String: Any] {
        ["panes": entries.map { entry -> [String: Any] in
            var pane: [String: Any] = ["pane_id": entry.pane]
            if let session = entry.session { pane["agent_session"] = ["value": session] }
            return pane
        }]
    }

    func testFindsThePaneThatHoldsTheChatAcrossSockets() {
        let event = AgentEvent(agentID: "codex-\(chat)", status: .needsInput)
        let target = HerdrFocus.locate(event: event, socketPaths: ["/a.sock", "/b.sock"]) { socket, _, _ in
            socket == "/a.sock"
                ? self.panes([("w1:p1", "someone-else")])
                : self.panes([("w2:p1", "other"), ("w1D:p3", self.chat.uppercased())])
        }
        XCTAssertEqual(target, HerdrTarget(socketPath: "/b.sock", paneID: "w1D:p3"))
    }

    func testUsesRecordedPaneUnlessItBelongsToAnotherChat() {
        let event = AgentEvent(agentID: "codex-\(chat)", status: .needsInput,
                               herdrPaneID: "w3:p2", herdrSocketPath: "/a.sock")
        func locate(owner: String?) -> HerdrTarget? {
            HerdrFocus.locate(event: event, socketPaths: ["/a.sock"]) { _, _, _ in
                self.panes([("w3:p2", owner)])
            }
        }
        XCTAssertEqual(locate(owner: nil)?.paneID, "w3:p2")
        XCTAssertEqual(locate(owner: chat)?.paneID, "w3:p2")
        XCTAssertNil(locate(owner: "another-chat"))
    }

    func testFindsPaneWithoutChatIDByItsTitle() {
        let event = AgentEvent(agentID: "codex-\(chat)", project: "workspace", status: .needsInput,
                               title: "Markster Direkt private preview and pilot")
        func pane(_ id: String, _ title: String, owner: String? = nil) -> [String: Any] {
            var entry: [String: Any] = ["pane_id": id, "terminal_title_stripped": title]
            if let owner { entry["agent_session"] = ["value": owner] }
            return entry
        }
        let list: [String: Any] = ["panes": [
            pane("a:p1", "Other chat | workspace"),
            pane("b:p1", "Markster Direkt private preview and pilot | markster-core"),
            pane("c:p1", "Markster Direkt private preview and pilot | workspace", owner: "someone-else"),
            pane("d:p1", "Markster Direkt private preview a... | workspace"),
        ]]
        let target = HerdrFocus.locate(event: event, socketPaths: ["/a.sock"]) { _, _, _ in list }
        XCTAssertEqual(target?.paneID, "d:p1")
    }

    func testUnreachableSocketsAreSkipped() {
        let event = AgentEvent(agentID: "codex-\(chat)", status: .needsInput)
        let target = HerdrFocus.locate(event: event, socketPaths: ["/dead.sock", "/live.sock"]) { socket, _, _ in
            if socket == "/dead.sock" { throw FocusError.activationFailed("down") }
            return self.panes([("w1:p1", self.chat)])
        }
        XCTAssertEqual(target?.socketPath, "/live.sock")
        XCTAssertNil(HerdrFocus.locate(event: event, socketPaths: [], request: { _, _, _ in [:] }))
    }

    func testHookInsideAPaneRecordsItsAddress() throws {
        let input = HookBridgeInput(tool: .codex, payload: ["session_id": .string("abc")],
                                    environment: ["HERDR_PANE_ID": "w1D:p1",
                                                  "HERDR_SOCKET_PATH": "/tmp/herdr.sock", "TERM_PROGRAM": "ghostty"])
        guard case .emit(let event) = HookBridge.action(for: input) else { return XCTFail("Missing alert") }
        XCTAssertEqual(event.herdrPaneID, "w1D:p1")
        XCTAssertEqual(event.herdrSocketPath, "/tmp/herdr.sock")
        XCTAssertEqual(try JSONDecoder().decode(AgentEvent.self, from: JSONEncoder().encode(event)), event)
        let legacy = try JSONDecoder().decode(
            AgentEvent.self, from: Data(#"{"agent_id":"codex-old","status":"needs_input","timestamp":1}"#.utf8)
        )
        XCTAssertNil(legacy.herdrPaneID)
    }

    func testAnotherHerdrPaneIsNotAcknowledgedBySharedTerminal() {
        let event = AgentEvent(agentID: "codex-chat", status: .needsInput, terminal: "ghostty",
                               tty: "/dev/ttys012", herdrPaneID: "w1:p1")
        let context = FrontmostSessionContext(terminalName: "ghostty", ttyPath: "/dev/ttys012")
        XCTAssertFalse(FrontmostSessionMatcher.matches(event: event, context: context))
    }
}
