import Foundation

public enum ShellProfile: String, CaseIterable, Sendable {
    case zsh
    case bash

    public init?(shellPath: String) {
        let name = URL(fileURLWithPath: shellPath).lastPathComponent.lowercased()
        switch name {
        case "zsh":
            self = .zsh
        case "bash":
            self = .bash
        default:
            return nil
        }
    }

    var rcRelativePath: String {
        switch self {
        case .zsh:
            return ".zshrc"
        case .bash:
            return ".bashrc"
        }
    }

    var snippetRelativePath: String {
        switch self {
        case .zsh:
            return ".config/overwatchr/shell.zsh"
        case .bash:
            return ".config/overwatchr/shell.bash"
        }
    }
}

public struct ShellIntegrationInstallResult: Sendable {
    public let shell: ShellProfile
    public let rcFile: URL
    public let snippetFile: URL
    public let notes: [String]
}

public struct ShellIntegrationStatus: Sendable {
    public let shell: ShellProfile
    public let rcFile: URL
    public let snippetFile: URL
    public let installed: Bool
}

public struct ShellIntegrationInstaller {
    private let fileManager: FileManager
    private let userHomeDirectoryURL: URL

    public init(
        fileManager: FileManager = .default,
        userHomeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.userHomeDirectoryURL = userHomeDirectoryURL
    }

    public func install(shell: ShellProfile) throws -> ShellIntegrationInstallResult {
        let rcURL = userHomeDirectoryURL.appendingPathComponent(shell.rcRelativePath)
        let snippetURL = userHomeDirectoryURL.appendingPathComponent(shell.snippetRelativePath)

        try ensureDirectory(snippetURL.deletingLastPathComponent())
        try ensureFileExists(at: rcURL)
        try shell.snippetContents.write(to: snippetURL, atomically: true, encoding: .utf8)
        try installSourceLine(into: rcURL, snippetURL: snippetURL)

        return ShellIntegrationInstallResult(
            shell: shell,
            rcFile: rcURL,
            snippetFile: snippetURL,
            notes: [
                "Interactive \(shell.rawValue) shells will export OVERWATCHR_TITLE from the current directory name.",
                "Ghostty tabs will use the same title, so Overwatchr can jump back to the correct session more reliably."
            ]
        )
    }

    public func status(for shell: ShellProfile) -> ShellIntegrationStatus {
        let rcURL = userHomeDirectoryURL.appendingPathComponent(shell.rcRelativePath)
        let snippetURL = userHomeDirectoryURL.appendingPathComponent(shell.snippetRelativePath)
        let sourceLine = expectedSourceLine(for: snippetURL)
        let snippetExists = fileManager.fileExists(atPath: snippetURL.path)
        let rcContents = (try? String(contentsOf: rcURL, encoding: .utf8)) ?? ""
        let installed = snippetExists && rcContents.contains(sourceLine)

        return ShellIntegrationStatus(
            shell: shell,
            rcFile: rcURL,
            snippetFile: snippetURL,
            installed: installed
        )
    }

    private func installSourceLine(into rcURL: URL, snippetURL: URL) throws {
        let existing = (try? String(contentsOf: rcURL, encoding: .utf8)) ?? ""
        let sourceLine = expectedSourceLine(for: snippetURL)
        let marker = "# Added by overwatchr"

        if existing.contains(sourceLine) {
            return
        }

        let prefix = existing.isEmpty ? "" : existing.trimmingCharacters(in: .newlines) + "\n\n"
        let updated = prefix + marker + "\n" + sourceLine + "\n"
        try updated.write(to: rcURL, atomically: true, encoding: .utf8)
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func ensureFileExists(at url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else {
            return
        }
        try "".write(to: url, atomically: true, encoding: .utf8)
    }

    private func snippetRelativePath(for snippetURL: URL) -> String {
        let homePath = userHomeDirectoryURL.path
        let snippetPath = snippetURL.path
        if snippetPath.hasPrefix(homePath + "/") {
            return String(snippetPath.dropFirst(homePath.count + 1))
        }
        return snippetPath
    }

    private func expectedSourceLine(for snippetURL: URL) -> String {
        let relativeSnippetPath = snippetRelativePath(for: snippetURL)
        return #"[[ -f "$HOME/\#(relativeSnippetPath)" ]] && source "$HOME/\#(relativeSnippetPath)""#
    }
}

private extension ShellProfile {
    var snippetContents: String {
        switch self {
        case .zsh:
            return """
            # Added by overwatchr
            if [ -n "${_OVERWATCHR_SHELL_ZSH_LOADED:-}" ]; then
              return 0
            fi
            export _OVERWATCHR_SHELL_ZSH_LOADED=1

            _overwatchr_shell_title() {
              local title
              title="${OVERWATCHR_TITLE_OVERRIDE:-${OVERWATCHR_PROJECT_NAME:-${PWD:t}}}"
              if [ -n "$title" ]; then
                export OVERWATCHR_TITLE="$title"
                printf '\\033]0;%s\\007' "$title"
              fi
            }

            autoload -Uz add-zsh-hook 2>/dev/null || true
            if typeset -f add-zsh-hook >/dev/null 2>&1; then
              add-zsh-hook chpwd _overwatchr_shell_title
              add-zsh-hook precmd _overwatchr_shell_title
            else
              precmd_functions+=(_overwatchr_shell_title)
              chpwd_functions+=(_overwatchr_shell_title)
            fi

            _overwatchr_shell_title
            """
        case .bash:
            return """
            # Added by overwatchr
            if [ -n "${_OVERWATCHR_SHELL_BASH_LOADED:-}" ]; then
              return 0
            fi
            export _OVERWATCHR_SHELL_BASH_LOADED=1

            _overwatchr_shell_title() {
              local title
              title="${OVERWATCHR_TITLE_OVERRIDE:-${OVERWATCHR_PROJECT_NAME:-${PWD##*/}}}"
              if [ -n "$title" ]; then
                export OVERWATCHR_TITLE="$title"
                printf '\\033]0;%s\\007' "$title"
              fi
            }

            case ";${PROMPT_COMMAND:-};" in
              *";_overwatchr_shell_title;"*) ;;
              *) PROMPT_COMMAND="_overwatchr_shell_title${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
            esac

            _overwatchr_shell_title
            """
        }
    }
}
