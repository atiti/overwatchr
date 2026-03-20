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
                "Interactive \(shell.rawValue) shells will export OVERWATCHR_TITLE from the current directory name plus a short terminal suffix when available.",
                "The shell will also emit the same title through the standard OSC title escape sequence.",
                "On Ghostty 1.3.1+, the focused tab title is updated through AppleScript for more reliable session targeting."
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

            _overwatchr_title_suffix() {
              local tty_path tty_name
              tty_path="$(tty 2>/dev/null || true)"
              if [ -z "$tty_path" ] || [ "$tty_path" = "not a tty" ] || [ "$tty_path" = "/dev/tty" ]; then
                return 0
              fi
              tty_name="${tty_path##*/}"
              print -r -- "$tty_name"
            }

            _overwatchr_compute_title() {
              local base suffix
              base="${OVERWATCHR_TITLE_OVERRIDE:-${OVERWATCHR_PROJECT_NAME:-${PWD:t}}}"
              suffix="$(_overwatchr_title_suffix)"

              if [ -n "$suffix" ]; then
                print -r -- "${base} · ${suffix}"
              else
                print -r -- "$base"
              fi
            }

            _overwatchr_write_title() {
              local title="$1"
              if [ -n "$title" ]; then
                printf '\\033]0;%s\\007' "$title"
              fi
            }

            _overwatchr_sync_ghostty_tab_title() {
              local title="$1"
              if [ "${TERM_PROGRAM:-}" != "ghostty" ] || [ -z "$title" ]; then
                return 0
              fi
              if [ "${_OVERWATCHR_LAST_GHOSTTY_TAB_TITLE:-}" = "$title" ]; then
                return 0
              fi

              OVERWATCHR_GHOSTTY_TITLE="$title" osascript >/dev/null 2>&1 <<'APPLESCRIPT'
            set desiredTitle to system attribute "OVERWATCHR_GHOSTTY_TITLE"
            tell application "Ghostty"
              if not frontmost then return
              perform action ("set_tab_title:" & desiredTitle) on focused terminal of selected tab of front window
            end tell
            APPLESCRIPT

              if [ $? -eq 0 ]; then
                export _OVERWATCHR_LAST_GHOSTTY_TAB_TITLE="$title"
              fi
            }

            _overwatchr_shell_title() {
              local title
              title="$(_overwatchr_compute_title)"
              if [ -n "$title" ]; then
                export OVERWATCHR_TITLE="$title"
                _overwatchr_write_title "$title"
                _overwatchr_sync_ghostty_tab_title "$title"
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

            _overwatchr_title_suffix() {
              local tty_path tty_name
              tty_path="$(tty 2>/dev/null || true)"
              if [ -z "$tty_path" ] || [ "$tty_path" = "not a tty" ] || [ "$tty_path" = "/dev/tty" ]; then
                return 0
              fi
              tty_name="${tty_path##*/}"
              printf '%s' "$tty_name"
            }

            _overwatchr_compute_title() {
              local base suffix
              base="${OVERWATCHR_TITLE_OVERRIDE:-${OVERWATCHR_PROJECT_NAME:-${PWD##*/}}}"
              suffix="$(_overwatchr_title_suffix)"

              if [ -n "$suffix" ]; then
                printf '%s · %s' "$base" "$suffix"
              else
                printf '%s' "$base"
              fi
            }

            _overwatchr_write_title() {
              local title="$1"
              if [ -n "$title" ]; then
                printf '\\033]0;%s\\007' "$title"
              fi
            }

            _overwatchr_sync_ghostty_tab_title() {
              local title="$1"
              if [ "${TERM_PROGRAM:-}" != "ghostty" ] || [ -z "$title" ]; then
                return 0
              fi
              if [ "${_OVERWATCHR_LAST_GHOSTTY_TAB_TITLE:-}" = "$title" ]; then
                return 0
              fi

              OVERWATCHR_GHOSTTY_TITLE="$title" osascript >/dev/null 2>&1 <<'APPLESCRIPT'
            set desiredTitle to system attribute "OVERWATCHR_GHOSTTY_TITLE"
            tell application "Ghostty"
              if not frontmost then return
              perform action ("set_tab_title:" & desiredTitle) on focused terminal of selected tab of front window
            end tell
            APPLESCRIPT

              if [ $? -eq 0 ]; then
                export _OVERWATCHR_LAST_GHOSTTY_TAB_TITLE="$title"
              fi
            }

            _overwatchr_shell_title() {
              local title
              title="$(_overwatchr_compute_title)"
              if [ -n "$title" ]; then
                export OVERWATCHR_TITLE="$title"
                _overwatchr_write_title "$title"
                _overwatchr_sync_ghostty_tab_title "$title"
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
