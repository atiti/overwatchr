import XCTest
@testable import OverwatchrCore

final class ShellIntegrationInstallerTests: XCTestCase {
    func testInstallZshWritesManagedSnippetAndSourceLine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = ShellIntegrationInstaller(userHomeDirectoryURL: root)
        let result = try installer.install(shell: .zsh)

        let rcContents = try String(contentsOf: result.rcFile, encoding: .utf8)
        let snippetContents = try String(contentsOf: result.snippetFile, encoding: .utf8)

        XCTAssertTrue(rcContents.contains(#"source "$HOME/.config/overwatchr/shell.zsh""#))
        XCTAssertTrue(snippetContents.contains("export OVERWATCHR_TITLE=\"$title\""))
        XCTAssertTrue(snippetContents.contains(#"printf '\033]0;%s\007' "$title""#))
        XCTAssertTrue(snippetContents.contains(#"perform action ("set_tab_title:" & desiredTitle) on focused terminal of selected tab of front window"#))
        XCTAssertFalse(snippetContents.contains("codex() {"))
    }

    func testInstallDoesNotDuplicateSourceLine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = ShellIntegrationInstaller(userHomeDirectoryURL: root)
        _ = try installer.install(shell: .zsh)
        _ = try installer.install(shell: .zsh)

        let rcURL = root.appendingPathComponent(".zshrc")
        let rcContents = try String(contentsOf: rcURL, encoding: .utf8)
        XCTAssertEqual(rcContents.components(separatedBy: #"source "$HOME/.config/overwatchr/shell.zsh""#).count - 1, 1)
    }

    func testStatusReflectsInstalledSnippetAndSourceLine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = ShellIntegrationInstaller(userHomeDirectoryURL: root)
        XCTAssertFalse(installer.status(for: .zsh).installed)

        _ = try installer.install(shell: .zsh)

        let status = installer.status(for: .zsh)
        XCTAssertTrue(status.installed)
        XCTAssertEqual(status.rcFile.path, root.appendingPathComponent(".zshrc").path)
        XCTAssertEqual(status.snippetFile.path, root.appendingPathComponent(".config/overwatchr/shell.zsh").path)
    }
}
