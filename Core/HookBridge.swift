import Foundation

public enum HookBridgeTool: String, CaseIterable, Sendable {
    case codex
    case claude
    case opencode
}

public enum HookBridgeAction: Equatable, Sendable {
    case emit(AgentEvent)
    case ignore
}

public enum JSONValue: Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self {
            return value
        }
        if case .string(let value) = self {
            return Double(value)
        }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }
}

public struct HookBridgeInput: Sendable {
    public let tool: HookBridgeTool
    public let payload: [String: JSONValue]
    public let environment: [String: String]
    public let currentDirectoryPath: String
    public let ttyPath: String?

    public init(
        tool: HookBridgeTool,
        payload: [String: JSONValue],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        ttyPath: String? = nil
    ) {
        self.tool = tool
        self.payload = payload
        self.environment = environment
        self.currentDirectoryPath = currentDirectoryPath
        self.ttyPath = (ttyPath ?? ControllingTTY.current())?.sanitizedTTYPath
    }
}

public enum HookBridge {
    public static func action(for input: HookBridgeInput) -> HookBridgeAction {
        switch input.tool {
        case .codex:
            return codexAction(for: input)
        case .claude:
            return claudeAction(for: input)
        case .opencode:
            return opencodeAction(for: input)
        }
    }

    private static func codexAction(for input: HookBridgeInput) -> HookBridgeAction {
        if input.bool("stop_hook_active") == true {
            return .ignore
        }

        return .emit(
            AgentEvent(
                agentID: namespacedAgentID(tool: .codex, rawID: inferredSessionIdentifier(from: input) ?? inferredProject(from: input)),
                project: inferredProject(from: input),
                status: .needsInput,
                terminal: inferredTerminal(from: input),
                tty: inferredTTY(from: input),
                title: inferredTitle(from: input),
                timestamp: input.double("timestamp") ?? Date().timeIntervalSince1970
            )
        )
    }

    private static func claudeAction(for input: HookBridgeInput) -> HookBridgeAction {
        let hookEventName = input.string("hook_event_name") ?? "Stop"

        switch hookEventName {
        case "SessionEnd":
            return .emit(
                AgentEvent(
                    agentID: namespacedAgentID(tool: .claude, rawID: inferredSessionIdentifier(from: input) ?? inferredProject(from: input)),
                    project: inferredProject(from: input),
                    status: .done,
                    terminal: inferredTerminal(from: input),
                    tty: inferredTTY(from: input),
                    title: inferredTitle(from: input),
                    timestamp: input.double("timestamp") ?? Date().timeIntervalSince1970
                )
            )
        case "Stop", "SubagentStop":
            if input.bool("stop_hook_active") == true {
                return .ignore
            }

            let rawID = input.string("agent_id") ?? inferredSessionIdentifier(from: input) ?? inferredProject(from: input)
            return .emit(
                AgentEvent(
                    agentID: namespacedAgentID(tool: .claude, rawID: rawID),
                    project: inferredProject(from: input),
                    status: .needsInput,
                    terminal: inferredTerminal(from: input),
                    tty: inferredTTY(from: input),
                    title: inferredTitle(from: input),
                    timestamp: input.double("timestamp") ?? Date().timeIntervalSince1970
                )
            )
        default:
            return .ignore
        }
    }

    private static func opencodeAction(for input: HookBridgeInput) -> HookBridgeAction {
        let eventType = input.string("type")
            ?? input.string("event.type")
            ?? input.string("event_name")

        switch eventType {
        case "session.idle":
            return .emit(
                AgentEvent(
                    agentID: namespacedAgentID(tool: .opencode, rawID: inferredSessionIdentifier(from: input) ?? inferredProject(from: input)),
                    project: inferredProject(from: input),
                    status: .needsInput,
                    terminal: inferredTerminal(from: input),
                    tty: inferredTTY(from: input),
                    title: inferredTitle(from: input),
                    timestamp: input.double("timestamp") ?? Date().timeIntervalSince1970
                )
            )
        case "session.end", "session.completed":
            return .emit(
                AgentEvent(
                    agentID: namespacedAgentID(tool: .opencode, rawID: inferredSessionIdentifier(from: input) ?? inferredProject(from: input)),
                    project: inferredProject(from: input),
                    status: .done,
                    terminal: inferredTerminal(from: input),
                    tty: inferredTTY(from: input),
                    title: inferredTitle(from: input),
                    timestamp: input.double("timestamp") ?? Date().timeIntervalSince1970
                )
            )
        default:
            return .ignore
        }
    }

    private static func inferredSessionIdentifier(from input: HookBridgeInput) -> String? {
        input.string("agent_id")
            ?? input.string("session_id")
            ?? input.string("conversation_id")
            ?? basename(input.string("transcript_path"))
            ?? basename(input.string("agent_transcript_path"))
    }

    private static func inferredProject(from input: HookBridgeInput) -> String? {
        basename(input.string("cwd")) ?? basename(input.currentDirectoryPath)
    }

    private static func inferredTitle(from input: HookBridgeInput) -> String? {
        input.environment["OVERWATCHR_TITLE"]?.nilIfBlank
            ?? basename(input.string("cwd"))
            ?? basename(input.currentDirectoryPath)
    }

    private static func inferredTerminal(from input: HookBridgeInput) -> String? {
        if let explicit = input.environment["OVERWATCHR_TERMINAL"]?.nilIfBlank {
            return explicit
        }

        switch input.environment["TERM_PROGRAM"]?.lowercased() {
        case "ghostty":
            return "ghostty"
        case "iterm.app", "iterm2":
            return "iTerm2"
        case "apple_terminal":
            return "Terminal"
        default:
            return nil
        }
    }

    private static func inferredTTY(from input: HookBridgeInput) -> String? {
        input.environment["OVERWATCHR_TTY"]?.sanitizedTTYPath
            ?? input.string("tty")?.sanitizedTTYPath
            ?? input.string("terminal.tty")?.sanitizedTTYPath
            ?? input.ttyPath?.sanitizedTTYPath
    }

    private static func namespacedAgentID(tool: HookBridgeTool, rawID: String?) -> String {
        let suffix = rawID?.nilIfBlank ?? tool.rawValue
        return "\(tool.rawValue)-\(suffix)"
    }

    private static func basename(_ path: String?) -> String? {
        guard let path = path?.nilIfBlank else {
            return nil
        }

        let standardized = URL(fileURLWithPath: path).lastPathComponent
        return standardized.nilIfBlank
    }
}

public enum HookBridgePayload {
    public static func decodeJSON(from data: Data) throws -> [String: JSONValue] {
        guard !data.isEmpty else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        if case .object(let dictionary) = try jsonValue(from: object) {
            return dictionary
        }
        return [:]
    }

    private static func jsonValue(from value: Any) throws -> JSONValue {
        switch value {
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let number as NSNumber:
            return .number(number.doubleValue)
        case let dictionary as [String: Any]:
            return .object(try dictionary.mapValues(jsonValue(from:)))
        case let array as [Any]:
            return .array(try array.map(jsonValue(from:)))
        default:
            return .null
        }
    }
}

private extension HookBridgeInput {
    func string(_ key: String) -> String? {
        if key.contains(".") {
            return nestedValue(for: key)?.stringValue
        }
        return payload[key]?.stringValue
    }

    func bool(_ key: String) -> Bool? {
        if key.contains(".") {
            return nestedValue(for: key)?.boolValue
        }
        return payload[key]?.boolValue
    }

    func double(_ key: String) -> Double? {
        if key.contains(".") {
            return nestedValue(for: key)?.doubleValue
        }
        return payload[key]?.doubleValue
    }

    private func nestedValue(for dottedKey: String) -> JSONValue? {
        let path = dottedKey.split(separator: ".").map(String.init)
        guard let first = path.first else {
            return nil
        }

        var current = payload[first]
        for component in path.dropFirst() {
            current = current?.objectValue?[component]
        }
        return current
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var sanitizedTTYPath: String? {
        guard let trimmed = nilIfBlank, trimmed != "/dev/tty" else {
            return nil
        }
        return trimmed
    }
}
