import XCTest
@testable import OverwatchrCore

final class HookBridgeTests: XCTestCase {
    func testCodexStopHookEmitsAlert() {
        let input = HookBridgeInput(
            tool: .codex,
            payload: [
                "cwd": .string("/tmp/landing"),
                "session_id": .string("sess-123"),
                "stop_hook_active": .bool(false)
            ],
            environment: ["TERM_PROGRAM": "ghostty"],
            currentDirectoryPath: "/tmp/landing"
        )

        guard case .emit(let event) = HookBridge.action(for: input) else {
            return XCTFail("Expected an emitted event")
        }

        XCTAssertEqual(event.agentID, "codex-sess-123")
        XCTAssertEqual(event.project, "landing")
        XCTAssertEqual(event.terminal, "ghostty")
        XCTAssertEqual(event.title, "landing")
        XCTAssertEqual(event.status, .needsInput)
    }

    func testClaudeSessionEndEmitsDone() {
        let input = HookBridgeInput(
            tool: .claude,
            payload: [
                "cwd": .string("/tmp/backend"),
                "session_id": .string("sess-claude"),
                "hook_event_name": .string("SessionEnd")
            ],
            currentDirectoryPath: "/tmp/backend"
        )

        guard case .emit(let event) = HookBridge.action(for: input) else {
            return XCTFail("Expected an emitted event")
        }

        XCTAssertEqual(event.agentID, "claude-sess-claude")
        XCTAssertEqual(event.project, "backend")
        XCTAssertEqual(event.status, .done)
    }

    func testClaudeStopHookActiveSuppressesDuplicateAlert() {
        let input = HookBridgeInput(
            tool: .claude,
            payload: [
                "cwd": .string("/tmp/backend"),
                "session_id": .string("sess-claude"),
                "hook_event_name": .string("Stop"),
                "stop_hook_active": .bool(true)
            ],
            currentDirectoryPath: "/tmp/backend"
        )

        XCTAssertEqual(HookBridge.action(for: input), .ignore)
    }

    func testOpenCodeIdleEmitsAlert() {
        let input = HookBridgeInput(
            tool: .opencode,
            payload: [
                "type": .string("session.idle"),
                "cwd": .string("/tmp/frontend")
            ],
            currentDirectoryPath: "/tmp/frontend"
        )

        guard case .emit(let event) = HookBridge.action(for: input) else {
            return XCTFail("Expected an emitted event")
        }

        XCTAssertEqual(event.agentID, "opencode-frontend")
        XCTAssertEqual(event.project, "frontend")
        XCTAssertEqual(event.status, .needsInput)
    }
}
