import XCTest
@testable import OverwatchrCore

final class TerminalApplicationTests: XCTestCase {
    func testGhosttyWorkingDirectoryFocusScriptMatchesBasename() {
        let script = TerminalApplication.ghostty.appleScriptWindowFocusCommand(
            matchingWorkingDirectoryBasename: "espclaw"
        )

        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains(#"working directory of t"#) == true)
        XCTAssertTrue(script?.contains(#"ends with ("/" & query)"#) == true)
        XCTAssertTrue(script?.contains(#"focus t"#) == true)
    }

    func testITermDoesNotExposeGhosttyWorkingDirectoryScript() {
        XCTAssertNil(TerminalApplication.iTerm.appleScriptWindowFocusCommand(
            matchingWorkingDirectoryBasename: "espclaw"
        ))
    }

    func testGhosttyExposesFrontWorkingDirectoryScript() {
        let script = TerminalApplication.ghostty.appleScriptFrontWorkingDirectoryBasenameCommand

        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("working directory of focused terminal of selected tab of front window") == true)
    }

    func testITermExposesFrontSessionTTYScript() {
        let script = TerminalApplication.iTerm.appleScriptFrontSessionTTYCommand

        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("tty of current session of current tab of front window") == true)
    }

    func testOtherActivationScriptEscapesBackslashBeforeQuote() {
        let terminal = TerminalApplication(name: #"Evil\" Terminal"#)
        let scripts = terminal.appleScriptActivationCommands

        XCTAssertEqual(scripts.count, 1)
        // A raw backslash-quote in the name must not let the parser interpret
        // `\\` as an escaped backslash immediately followed by an unescaped
        // quote, which would terminate the AppleScript string literal early.
        XCTAssertTrue(scripts.first?.contains(#"tell application "Evil\\\" Terminal""#) == true)
    }
}
