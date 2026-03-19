import Foundation
import OverwatchrCore

enum CLIError: Error, LocalizedError {
    case usage(String)
    case missingValue(String)
    case invalidValue(option: String, value: String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .invalidValue(let option, let value):
            return "Invalid value for \(option): \(value)"
        }
    }
}

struct ParsedCommand {
    let name: String
    let positionals: [String]
    let options: [String: String]
}

@main
struct OverwatchrCLI {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else {
                throw CLIError.usage("Missing command.")
            }

            switch command {
            case "alert", "done", "error":
                let parsed = try parseCommand(arguments)
                let event = try makeEvent(from: parsed)
                try EventStore().append(event)
                print("Recorded \(event.status.rawValue) for \(event.agentID)")
            case "hooks":
                try runHooksCommand(arguments: Array(arguments.dropFirst()))
            case "shell":
                try runShellCommand(arguments: Array(arguments.dropFirst()))
            case "hook-run":
                try runHookBridge(arguments: Array(arguments.dropFirst()))
            case "--help", "-h", "help":
                throw CLIError.usage("overwatchr command reference")
            default:
                throw CLIError.usage("Unknown command: \(command)")
            }
        } catch {
            fputs("\(error.localizedDescription)\n\n\(usage)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func parseCommand(_ arguments: [String]) throws -> ParsedCommand {
        guard let command = arguments.first else {
            throw CLIError.usage("Missing command.")
        }

        var options: [String: String] = [:]
        var positionals: [String] = []
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let nextIndex = index + 1
                guard nextIndex < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                options[String(argument.dropFirst(2))] = arguments[nextIndex]
                index += 2
            } else {
                positionals.append(argument)
                index += 1
            }
        }

        return ParsedCommand(name: command, positionals: positionals, options: options)
    }

    private static func makeEvent(from parsed: ParsedCommand) throws -> AgentEvent {
        let status: AgentStatus
        switch parsed.name {
        case "alert":
            status = .needsInput
        case "done":
            status = .done
        case "error":
            status = .error
        default:
            throw CLIError.usage("Unknown event command: \(parsed.name)")
        }

        guard let agent = parsed.options["agent"], !agent.isEmpty else {
            throw CLIError.usage("Missing required --agent option.")
        }

        return AgentEvent(
            agentID: agent,
            project: parsed.options["project"],
            status: status,
            terminal: parsed.options["terminal"],
            tty: parsed.options["tty"],
            title: parsed.options["title"],
            timestamp: parsed.options["timestamp"].flatMap(TimeInterval.init) ?? Date().timeIntervalSince1970
        )
    }

    private static func runHooksCommand(arguments: [String]) throws {
        let parsed = try parseCommand(["hooks"] + arguments)
        guard let subcommand = parsed.positionals.first else {
            throw CLIError.usage("Missing hooks subcommand.")
        }

        switch subcommand {
        case "install":
            try installHooks(from: parsed)
        default:
            throw CLIError.usage("Unknown hooks subcommand: \(subcommand)")
        }
    }

    private static func installHooks(from parsed: ParsedCommand) throws {
        guard parsed.positionals.count >= 2 else {
            throw CLIError.usage("Usage: overwatchr hooks install <codex|claude|opencode|all> [--scope project|user] [--dir PATH]")
        }

        guard let tool = IntegrationTool(rawValue: parsed.positionals[1]) else {
            throw CLIError.invalidValue(option: "tool", value: parsed.positionals[1])
        }

        let scope = try parseScope(parsed.options["scope"] ?? "project")
        let projectDirectoryURL = URL(fileURLWithPath: parsed.options["dir"] ?? FileManager.default.currentDirectoryPath, isDirectory: true)
        let binaryPath = parsed.options["overwatchr-path"] ?? resolvedExecutablePath()

        let installer = IntegrationInstaller()
        let results = try installer.install(
            tool: tool,
            scope: scope,
            projectDirectoryURL: projectDirectoryURL,
            overwatchrBinaryPath: binaryPath
        )

        for result in results {
            print("Installed \(result.tool.rawValue) hooks (\(result.scope.rawValue)):")
            for file in result.files {
                print("  - \(file.path)")
            }
            for note in result.notes {
                print("    \(note)")
            }
        }
    }

    private static func runHookBridge(arguments: [String]) throws {
        guard let rawTool = arguments.first, let tool = HookBridgeTool(rawValue: rawTool) else {
            throw CLIError.usage("Usage: overwatchr hook-run <codex|claude|opencode>")
        }

        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        let payload = try HookBridgePayload.decodeJSON(from: stdinData)
        let input = HookBridgeInput(tool: tool, payload: payload)

        switch HookBridge.action(for: input) {
        case .ignore:
            break
        case .emit(let event):
            try EventStore().append(event)
        }
    }

    private static func runShellCommand(arguments: [String]) throws {
        let parsed = try parseCommand(["shell"] + arguments)
        guard let subcommand = parsed.positionals.first else {
            throw CLIError.usage("Missing shell subcommand.")
        }

        switch subcommand {
        case "install":
            try installShellIntegration(from: parsed)
        default:
            throw CLIError.usage("Unknown shell subcommand: \(subcommand)")
        }
    }

    private static func installShellIntegration(from parsed: ParsedCommand) throws {
        let shell = try parseShell(parsed.options["shell"] ?? "auto")
        let result = try ShellIntegrationInstaller().install(shell: shell)

        print("Installed \(result.shell.rawValue) shell integration:")
        print("  - \(result.rcFile.path)")
        print("  - \(result.snippetFile.path)")
        for note in result.notes {
            print("    \(note)")
        }
    }

    private static func parseScope(_ rawValue: String) throws -> IntegrationScope {
        guard let scope = IntegrationScope(rawValue: rawValue) else {
            throw CLIError.invalidValue(option: "scope", value: rawValue)
        }
        return scope
    }

    private static func parseShell(_ rawValue: String) throws -> ShellProfile {
        if rawValue == "auto" {
            if let shell = ShellProfile(shellPath: ProcessInfo.processInfo.environment["SHELL"] ?? "") {
                return shell
            }
            throw CLIError.usage("Could not detect the current shell. Pass --shell zsh or --shell bash.")
        }

        guard let shell = ShellProfile(rawValue: rawValue) else {
            throw CLIError.invalidValue(option: "shell", value: rawValue)
        }
        return shell
    }

    private static func resolvedExecutablePath() -> String {
        let executablePath = CommandLine.arguments.first ?? "overwatchr"
        return URL(fileURLWithPath: executablePath).path
    }

    private static let usage = """
    Usage:
      overwatchr alert --agent AGENT [--project PROJECT] [--terminal TERMINAL] [--tty TTY] [--title TITLE]
      overwatchr done --agent AGENT [--project PROJECT]
      overwatchr error --agent AGENT [--project PROJECT] [--terminal TERMINAL] [--tty TTY] [--title TITLE]
      overwatchr hooks install <codex|claude|opencode|all> [--scope project|user] [--dir PATH]
      overwatchr shell install [--shell auto|zsh|bash]
      overwatchr hook-run <codex|claude|opencode>

    Examples:
      overwatchr alert --agent copy --project landing --terminal ghostty --tty /dev/ttys012 --title "landing:copy"
      overwatchr hooks install codex --scope project
      overwatchr hooks install all --scope user
      overwatchr shell install --shell zsh
    """
}
