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

    public var appleScriptWindowMenuItemsCommand: String? {
        switch self {
        case .ghostty:
            return """
            tell application "System Events"
                tell process "Ghostty"
                    get title of every menu item of menu 1 of menu bar item "Window" of menu bar 1
                end tell
            end tell
            """
        case .iTerm, .terminal, .other:
            return nil
        }
    }

    public var appleScriptFrontWindowTitleCommand: String? {
        let processName: String

        switch self {
        case .ghostty:
            processName = "Ghostty"
        case .iTerm:
            processName = "iTerm2"
        case .terminal:
            processName = "Terminal"
        case .other(let name):
            processName = name
        }

        let escapedProcessName = processName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        tell application "System Events"
            tell process "\(escapedProcessName)"
                get name of front window
            end tell
        end tell
        """
    }

    public func appleScriptSelectWindowMenuItemCommand(title: String) -> String? {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch self {
        case .ghostty:
            return """
            tell application "Ghostty"
                activate
            end tell
            delay 0.05
            tell application "System Events"
                tell process "Ghostty"
                    click menu item "\(escapedTitle)" of menu 1 of menu bar item "Window" of menu bar 1
                    return "matched"
                end tell
            end tell
            return ""
            """
        case .iTerm, .terminal, .other:
            return nil
        }
    }

    public func appleScriptWindowFocusCommand(matchingTTY tty: String) -> String? {
        let escapedTTY = tty
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch self {
        case .ghostty:
            return nil
        case .iTerm:
            return """
            tell application "iTerm2"
                activate
                set query to "\(escapedTTY)"
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            set sessionTTY to ""
                            try
                                set sessionTTY to (tty of aSession as text)
                            on error
                                set sessionTTY to ""
                            end try
                            if sessionTTY is query then
                                tell aWindow
                                    set current tab to aTab
                                    set index to 1
                                end tell
                                try
                                    select aSession
                                end try
                                return "matched"
                            end if
                        end repeat
                    end repeat
                end repeat
                return ""
            end tell
            """
        case .terminal:
            return """
            tell application "Terminal"
                activate
                set query to "\(escapedTTY)"
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        set tabTTY to ""
                        try
                            set tabTTY to (tty of aTab as text)
                        on error
                            set tabTTY to ""
                        end try
                        if tabTTY is query then
                            set selected tab of aWindow to aTab
                            set index of aWindow to 1
                            return "matched"
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
        case .other:
            return nil
        }
    }

    public func appleScriptWindowFocusCommand(matchingWorkingDirectoryBasename basename: String) -> String? {
        let escapedBasename = basename
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch self {
        case .ghostty:
            return """
            tell application "Ghostty"
                activate
                set query to "\(escapedBasename)"
                repeat with t in terminals
                    set workingDirectoryPath to ""
                    try
                        set workingDirectoryPath to (working directory of t as text)
                    on error
                        set workingDirectoryPath to ""
                    end try
                    if workingDirectoryPath is query or workingDirectoryPath ends with ("/" & query) then
                        focus t
                        return "matched"
                    end if
                end repeat
                return ""
            end tell
            """
        case .iTerm, .terminal, .other:
            return nil
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
