import Foundation

public enum IntegrationTool: String, CaseIterable, Sendable {
    case codex
    case claude
    case opencode
    case all

    public var concreteTools: [IntegrationTool] {
        switch self {
        case .all:
            return [.codex, .claude, .opencode]
        default:
            return [self]
        }
    }
}

public enum IntegrationScope: String, CaseIterable, Sendable {
    case project
    case user
}

public struct IntegrationInstallResult: Sendable {
    public let tool: IntegrationTool
    public let scope: IntegrationScope
    public let files: [URL]
    public let notes: [String]
}

public struct IntegrationInstaller {
    private let fileManager: FileManager
    private let userHomeDirectoryURL: URL

    public init(
        fileManager: FileManager = .default,
        userHomeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.userHomeDirectoryURL = userHomeDirectoryURL
    }

    public func install(
        tool: IntegrationTool,
        scope: IntegrationScope,
        projectDirectoryURL: URL,
        overwatchrBinaryPath: String
    ) throws -> [IntegrationInstallResult] {
        try tool.concreteTools.map { concrete in
            switch concrete {
            case .codex:
                return try installCodex(scope: scope, projectDirectoryURL: projectDirectoryURL, overwatchrBinaryPath: overwatchrBinaryPath)
            case .claude:
                return try installClaude(scope: scope, projectDirectoryURL: projectDirectoryURL, overwatchrBinaryPath: overwatchrBinaryPath)
            case .opencode:
                return try installOpencode(scope: scope, projectDirectoryURL: projectDirectoryURL, overwatchrBinaryPath: overwatchrBinaryPath)
            case .all:
                fatalError("Expanded before installation")
            }
        }
    }

    private func installCodex(
        scope: IntegrationScope,
        projectDirectoryURL: URL,
        overwatchrBinaryPath: String
    ) throws -> IntegrationInstallResult {
        let configDirectory = configDirectory(for: .codex, scope: scope, projectDirectoryURL: projectDirectoryURL)
        let configURL = configDirectory.appendingPathComponent("config.toml")
        let hooksURL = configDirectory.appendingPathComponent("hooks.json")
        let command = "\(quoted(overwatchrBinaryPath)) hook-run codex"

        try ensureDirectory(configDirectory)
        try writeCodexConfig(to: configURL)
        try installJSONHook(
            at: hooksURL,
            event: "Stop",
            replacementCommandSuffix: "hook-run codex",
            commandHook: [
                "type": "command",
                "command": command,
                "timeoutSec": 5,
                "statusMessage": "notifying overwatchr"
            ]
        )

        return IntegrationInstallResult(
            tool: .codex,
            scope: scope,
            files: [configURL, hooksURL],
            notes: ["Codex hooks are enabled and Overwatchr will react on Stop events."]
        )
    }

    private func installClaude(
        scope: IntegrationScope,
        projectDirectoryURL: URL,
        overwatchrBinaryPath: String
    ) throws -> IntegrationInstallResult {
        let settingsURL: URL
        switch scope {
        case .project:
            settingsURL = projectDirectoryURL.appendingPathComponent(".claude/settings.local.json")
        case .user:
            settingsURL = userHomeDirectoryURL.appendingPathComponent(".claude/settings.json")
        }

        try ensureDirectory(settingsURL.deletingLastPathComponent())
        let command = "\(quoted(overwatchrBinaryPath)) hook-run claude"

        try installJSONHook(
            at: settingsURL,
            event: "Stop",
            replacementCommandSuffix: "hook-run claude",
            commandHook: [
                "type": "command",
                "command": command,
                "timeout": 5,
                "statusMessage": "notifying overwatchr"
            ]
        )
        try installJSONHook(
            at: settingsURL,
            event: "SessionEnd",
            replacementCommandSuffix: "hook-run claude",
            commandHook: [
                "type": "command",
                "command": command,
                "timeout": 5,
                "statusMessage": "clearing overwatchr alert"
            ]
        )

        return IntegrationInstallResult(
            tool: .claude,
            scope: scope,
            files: [settingsURL],
            notes: ["Claude Code Stop alerts and SessionEnd cleanup are installed."]
        )
    }

    private func installOpencode(
        scope: IntegrationScope,
        projectDirectoryURL: URL,
        overwatchrBinaryPath: String
    ) throws -> IntegrationInstallResult {
        let pluginDirectory: URL
        switch scope {
        case .project:
            pluginDirectory = projectDirectoryURL.appendingPathComponent(".opencode/plugins", isDirectory: true)
        case .user:
            pluginDirectory = userHomeDirectoryURL.appendingPathComponent(".config/opencode/plugins", isDirectory: true)
        }

        let pluginURL = pluginDirectory.appendingPathComponent("overwatchr.js")
        try ensureDirectory(pluginDirectory)

        let plugin = """
        import { spawnSync } from "node:child_process"

        const binary = \(jsonStringLiteral(overwatchrBinaryPath))

        export const OverwatchrPlugin = async () => {
          return {
            event: async ({ event }) => {
              if (event?.type !== "session.idle" && event?.type !== "session.end" && event?.type !== "session.completed") {
                return
              }

              spawnSync(binary, ["hook-run", "opencode"], {
                input: JSON.stringify(event ?? {}),
                stdio: ["pipe", "ignore", "ignore"],
              })
            },
          }
        }
        """

        try plugin.write(to: pluginURL, atomically: true, encoding: .utf8)

        return IntegrationInstallResult(
            tool: .opencode,
            scope: scope,
            files: [pluginURL],
            notes: ["OpenCode plugin installed for session.idle alerts."]
        )
    }

    private func configDirectory(
        for tool: IntegrationTool,
        scope: IntegrationScope,
        projectDirectoryURL: URL
    ) -> URL {
        switch (tool, scope) {
        case (.codex, .project):
            return projectDirectoryURL.appendingPathComponent(".codex", isDirectory: true)
        case (.codex, .user):
            return userHomeDirectoryURL.appendingPathComponent(".codex", isDirectory: true)
        default:
            return projectDirectoryURL
        }
    }

    private func writeCodexConfig(to url: URL) throws {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        let updated: String
        if existing.range(of: #"(?m)^codex_hooks\s*="#, options: .regularExpression) != nil {
            updated = existing.replacingOccurrences(
                of: #"(?m)^codex_hooks\s*=.*$"#,
                with: "codex_hooks = true",
                options: .regularExpression
            )
        } else if existing.range(of: #"(?m)^\[features\]\s*$"#, options: .regularExpression) != nil {
            updated = existing.replacingOccurrences(
                of: #"(?m)^\[features\]\s*$"#,
                with: "[features]\ncodex_hooks = true",
                options: .regularExpression
            )
        } else if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated = "[features]\ncodex_hooks = true\n"
        } else {
            updated = existing.trimmingCharacters(in: .newlines) + "\n\n[features]\ncodex_hooks = true\n"
        }

        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private func installJSONHook(
        at url: URL,
        event: String,
        replacementCommandSuffix: String,
        commandHook: [String: Any]
    ) throws {
        var root = try loadJSONObject(from: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var groups = hooks[event] as? [[String: Any]] ?? []
        let command = commandHook["command"] as? String

        groups = groups.compactMap { group in
            var updatedGroup = group
            let handlers = group["hooks"] as? [[String: Any]] ?? []
            let filteredHandlers = handlers.filter { handler in
                guard let existingCommand = handler["command"] as? String else {
                    return true
                }
                return !existingCommand.contains(replacementCommandSuffix)
            }

            guard !filteredHandlers.isEmpty else {
                return nil
            }

            updatedGroup["hooks"] = filteredHandlers
            return updatedGroup
        }

        let alreadyInstalled = groups.contains { group in
            let handlers = group["hooks"] as? [[String: Any]] ?? []
            return handlers.contains { handler in
                handler["command"] as? String == command
            }
        }

        if !alreadyInstalled {
            groups.append(["hooks": [commandHook]])
        }

        hooks[event] = groups
        root["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    private func loadJSONObject(from url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            return [:]
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func quoted(_ string: String) -> String {
        if string.contains(" ") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return string
    }

    private func jsonStringLiteral(_ string: String) -> String {
        let encoded = try? JSONEncoder().encode(string)
        return encoded.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(string)\""
    }
}
