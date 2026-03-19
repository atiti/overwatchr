import Foundation
import OverwatchrCore

enum CLIError: Error, LocalizedError {
    case usage(String)
    case missingValue(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .missingValue(let option):
            return "Missing value for \(option)."
        }
    }
}

struct ParsedCommand {
    let name: String
    let options: [String: String]
}

@main
struct OverwatchrCLI {
    static func main() {
        do {
            let parsed = try parse(arguments: Array(CommandLine.arguments.dropFirst()))
            let event = try makeEvent(from: parsed)
            try EventStore().append(event)
            print("Recorded \(event.status.rawValue) for \(event.agentID)")
        } catch {
            fputs("\(error.localizedDescription)\n\n\(usage)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func parse(arguments: [String]) throws -> ParsedCommand {
        guard let command = arguments.first else {
            throw CLIError.usage("Missing command.")
        }

        if command == "--help" || command == "-h" {
            throw CLIError.usage("overwatchr command reference")
        }

        var options: [String: String] = [:]
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                throw CLIError.usage("Unexpected argument: \(argument)")
            }

            let nextIndex = index + 1
            guard nextIndex < arguments.count else {
                throw CLIError.missingValue(argument)
            }

            options[String(argument.dropFirst(2))] = arguments[nextIndex]
            index += 2
        }

        return ParsedCommand(name: command, options: options)
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
            throw CLIError.usage("Unknown command: \(parsed.name)")
        }

        guard let agent = parsed.options["agent"], !agent.isEmpty else {
            throw CLIError.usage("Missing required --agent option.")
        }

        return AgentEvent(
            agentID: agent,
            project: parsed.options["project"],
            status: status,
            terminal: parsed.options["terminal"],
            title: parsed.options["title"],
            timestamp: parsed.options["timestamp"].flatMap(TimeInterval.init) ?? Date().timeIntervalSince1970
        )
    }

    private static let usage = """
    Usage:
      overwatchr alert --agent AGENT [--project PROJECT] [--terminal TERMINAL] [--title TITLE]
      overwatchr done --agent AGENT [--project PROJECT]
      overwatchr error --agent AGENT [--project PROJECT] [--terminal TERMINAL] [--title TITLE]

    Examples:
      overwatchr alert --agent copy --project landing --terminal ghostty --title "landing:copy"
      overwatchr done --agent copy --project landing
      overwatchr error --agent api --project backend --terminal iTerm2 --title "backend:api"
    """
}

