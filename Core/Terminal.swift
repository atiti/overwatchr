import Foundation

public enum TerminalApplication: Equatable, Sendable {
    case ghostty
    case iTerm
    case terminal
    case other(String)

    public init(name: String) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "ghostty":
            self = .ghostty
        case "iterm", "iterm2":
            self = .iTerm
        case "terminal", "terminal.app", "apple terminal":
            self = .terminal
        default:
            self = .other(name)
        }
    }

    public var displayName: String {
        switch self {
        case .ghostty:
            return "Ghostty"
        case .iTerm:
            return "iTerm"
        case .terminal:
            return "Terminal"
        case .other(let name):
            return name
        }
    }

    public var bundleIdentifiers: [String] {
        switch self {
        case .ghostty:
            return ["com.mitchellh.ghostty"]
        case .iTerm:
            return ["com.googlecode.iterm2"]
        case .terminal:
            return ["com.apple.Terminal"]
        case .other:
            return []
        }
    }

    public var candidateNames: [String] {
        switch self {
        case .ghostty:
            return ["Ghostty"]
        case .iTerm:
            return ["iTerm2", "iTerm"]
        case .terminal:
            return ["Terminal"]
        case .other(let name):
            return [name]
        }
    }

    public var appleScriptActivationCommands: [String] {
        switch self {
        case .ghostty:
            return []
        case .iTerm:
            return [
                """
                tell application "iTerm2"
                    activate
                end tell
                """,
                """
                tell application "iTerm"
                    activate
                end tell
                """
            ]
        case .terminal:
            return [
                """
                tell application "Terminal"
                    activate
                end tell
                """
            ]
        case .other(let name):
            return [
                """
                tell application "\(name.replacingOccurrences(of: "\"", with: "\\\""))"
                    activate
                end tell
                """
            ]
        }
    }

    public func appleScriptWindowFocusCommand(matching title: String) -> String? {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch self {
        case .ghostty:
            return nil
        case .iTerm:
            return """
            tell application "iTerm2"
                activate
                set query to "\(escapedTitle)"
                repeat with aWindow in windows
                    try
                        set windowName to (name of aWindow as text)
                    on error
                        set windowName to ""
                    end try
                    if windowName contains query then
                        tell aWindow to set index to 1
                        return "matched"
                    end if
                    repeat with aTab in tabs of aWindow
                        set tabName to ""
                        try
                            set tabName to (name of current session of aTab as text)
                        on error
                            try
                                set tabName to (name of aTab as text)
                            on error
                                set tabName to ""
                            end try
                        end try
                        if tabName contains query then
                            tell aWindow
                                set current tab to aTab
                                set index to 1
                            end tell
                            return "matched"
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
        case .terminal:
            return nil
        case .other:
            return nil
        }
    }
}
