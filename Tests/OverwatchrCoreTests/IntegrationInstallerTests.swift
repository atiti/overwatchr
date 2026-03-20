import XCTest
@testable import OverwatchrCore

final class IntegrationInstallerTests: XCTestCase {
    func testCodexInstallWritesConfigAndHooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installer = IntegrationInstaller(
            fileManager: .default,
            userHomeDirectoryURL: root.appendingPathComponent("home", isDirectory: true)
        )

        let results = try installer.install(
            tool: .codex,
            scope: .project,
            projectDirectoryURL: root,
            overwatchrBinaryPath: "/usr/local/bin/overwatchr"
        )

        XCTAssertEqual(results.count, 1)
        let config = try String(contentsOf: root.appendingPathComponent(".codex/config.toml"))
        XCTAssertTrue(config.contains("codex_hooks = true"))

        let hooksData = try Data(contentsOf: root.appendingPathComponent(".codex/hooks.json"))
        let hooksObject = try JSONSerialization.jsonObject(with: hooksData) as? [String: Any]
        let hooks = hooksObject?["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["Stop"])
    }

    func testClaudeInstallPreservesExistingHooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let settingsURL = root.appendingPathComponent(".claude/settings.local.json")
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let existing = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo existing"
                  }
                ]
              }
            ]
          }
        }
        """
        try existing.write(to: settingsURL, atomically: true, encoding: .utf8)

        let installer = IntegrationInstaller(fileManager: .default, userHomeDirectoryURL: root.appendingPathComponent("home", isDirectory: true))
        _ = try installer.install(
            tool: .claude,
            scope: .project,
            projectDirectoryURL: root,
            overwatchrBinaryPath: "/usr/local/bin/overwatchr"
        )

        let data = try Data(contentsOf: settingsURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = object?["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["PreToolUse"])
        XCTAssertNotNil(hooks?["Stop"])
        XCTAssertNotNil(hooks?["SessionEnd"])
        XCTAssertNotNil(hooks?["PermissionRequest"])
    }

    func testInstallReplacesExistingOverwatchrCommandPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let settingsURL = root.appendingPathComponent(".claude/settings.local.json")
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let existing = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/tmp/old/overwatchr hook-run claude"
                  }
                ]
              }
            ]
          }
        }
        """
        try existing.write(to: settingsURL, atomically: true, encoding: .utf8)

        let installer = IntegrationInstaller(fileManager: .default, userHomeDirectoryURL: root.appendingPathComponent("home", isDirectory: true))
        _ = try installer.install(
            tool: .claude,
            scope: .project,
            projectDirectoryURL: root,
            overwatchrBinaryPath: "/usr/local/bin/overwatchr"
        )

        let data = try Data(contentsOf: settingsURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = object?["hooks"] as? [String: Any]
        let stopGroups = hooks?["Stop"] as? [[String: Any]] ?? []
        let commands = stopGroups
            .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .compactMap { $0["command"] as? String }

        XCTAssertEqual(commands, ["/usr/local/bin/overwatchr hook-run claude"])
    }

    func testOpenCodeInstallWritesPlugin() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installer = IntegrationInstaller(fileManager: .default, userHomeDirectoryURL: root.appendingPathComponent("home", isDirectory: true))

        _ = try installer.install(
            tool: .opencode,
            scope: .project,
            projectDirectoryURL: root,
            overwatchrBinaryPath: "/usr/local/bin/overwatchr"
        )

        let plugin = try String(contentsOf: root.appendingPathComponent(".opencode/plugins/overwatchr.js"))
        XCTAssertTrue(plugin.contains("hook-run"))
        XCTAssertTrue(plugin.contains("session.idle"))
    }
}
