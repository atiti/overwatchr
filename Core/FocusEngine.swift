#if os(macOS)
import AppKit
import ApplicationServices
import Foundation

public enum FocusError: Error, LocalizedError {
    case missingTerminal
    case applicationNotRunning(String)
    case accessibilityPermissionRequired
    case windowNotFound(String)
    case activationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingTerminal:
            return "This alert does not include terminal metadata."
        case .applicationNotRunning(let name):
            return "\(name) is not running."
        case .accessibilityPermissionRequired:
            return "Accessibility access is required to focus the matching terminal window."
        case .windowNotFound(let title):
            return "No matching terminal window was found for: \(title)"
        case .activationFailed(let message):
            return message
        }
    }
}

public struct FocusTarget: Sendable {
    public let terminalName: String
    public let ttyPath: String?
    public let titleSubstring: String?

    public init(terminalName: String, ttyPath: String?, titleSubstring: String?) {
        self.terminalName = terminalName
        self.ttyPath = ttyPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.titleSubstring = titleSubstring?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
public final class FocusEngine {
    public init() {}

    public func focus(event: AgentEvent) throws {
        guard let terminal = event.terminal else {
            throw FocusError.missingTerminal
        }

        let workingDirectoryQueries = [event.project, event.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, query in
                if !result.contains(query) {
                    result.append(query)
                }
            }

        try focus(
            target: FocusTarget(
                terminalName: terminal,
                ttyPath: event.tty,
                titleSubstring: FocusHintResolver.queries(for: event).first
            ),
            titleQueries: FocusHintResolver.queries(for: event),
            workingDirectoryQueries: workingDirectoryQueries
        )
    }

    public func focus(target: FocusTarget) throws {
        try focus(
            target: target,
            titleQueries: [target.titleSubstring].compactMap { $0 },
            workingDirectoryQueries: []
        )
    }

    private func focus(target: FocusTarget, titleQueries: [String], workingDirectoryQueries: [String]) throws {
        let terminal = TerminalApplication(name: target.terminalName)

        guard let app = findRunningApplication(for: terminal) else {
            throw FocusError.applicationNotRunning(terminal.displayName)
        }

        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        if let tty = target.ttyPath, !tty.isEmpty, runTTYMatchAppleScript(for: terminal, tty: tty) {
            return
        }

        for workingDirectory in workingDirectoryQueries where !workingDirectory.isEmpty {
            if runWorkingDirectoryMatchAppleScript(for: terminal, workingDirectoryBasename: workingDirectory) {
                return
            }
        }

        for title in titleQueries where !title.isEmpty {
            if runTitleMatchAppleScript(for: terminal, title: title) {
                return
            }

            let focused = try focusWindow(of: app, matching: title)
            if focused {
                return
            }
        }

        if runAppleScriptActivation(for: terminal) {
            return
        }

        if let title = titleQueries.first {
            throw FocusError.windowNotFound(title)
        }
    }

    private func findRunningApplication(for terminal: TerminalApplication) -> NSRunningApplication? {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        if let app = runningApps.first(where: { running in
            guard let bundleIdentifier = running.bundleIdentifier else {
                return false
            }
            return terminal.bundleIdentifiers.contains(bundleIdentifier)
        }) {
            return app
        }

        return runningApps.first(where: { running in
            guard let localizedName = running.localizedName else {
                return false
            }
            return terminal.candidateNames.contains { candidate in
                localizedName.caseInsensitiveCompare(candidate) == .orderedSame
            }
        })
    }

    private func focusWindow(of application: NSRunningApplication, matching title: String) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw FocusError.accessibilityPermissionRequired
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let windows = copyWindows(from: appElement)

        let scoredWindows: [(window: AXUIElement, score: Int)] = windows.compactMap { window in
            let candidates = windowCandidateStrings(for: window)
            let score = candidates
                .compactMap { WindowTitleMatcher.score(candidate: $0, query: title) }
                .max()

            guard let score else {
                return nil
            }

            return (window, score)
        }

        if let bestWindow = scoredWindows.max(by: { lhs, rhs in lhs.score < rhs.score })?.window {
            raise(window: bestWindow)
            return true
        }

        return false
    }

    private func runTTYMatchAppleScript(for terminal: TerminalApplication, tty: String) -> Bool {
        guard let scriptSource = terminal.appleScriptWindowFocusCommand(matchingTTY: tty),
              let output = executeAppleScript(scriptSource)?.stringValue else {
            return false
        }

        return output == "matched"
    }

    private func runWorkingDirectoryMatchAppleScript(
        for terminal: TerminalApplication,
        workingDirectoryBasename: String
    ) -> Bool {
        guard let scriptSource = terminal.appleScriptWindowFocusCommand(
            matchingWorkingDirectoryBasename: workingDirectoryBasename
        ),
              let output = executeAppleScript(scriptSource)?.stringValue else {
            return false
        }

        return output == "matched"
    }

    private func windowCandidateStrings(for window: AXUIElement) -> [String] {
        [
            copyStringAttribute(kAXTitleAttribute as CFString, from: window),
            copyStringAttribute(kAXDocumentAttribute as CFString, from: window)
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func raise(window: AXUIElement) {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private func copyWindows(from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else {
            return []
        }
        return array
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private func runAppleScriptActivation(for terminal: TerminalApplication) -> Bool {
        for command in terminal.appleScriptActivationCommands {
            if executeAppleScript(command) != nil {
                return true
            }
        }

        return false
    }

    private func runTitleMatchAppleScript(for terminal: TerminalApplication, title: String) -> Bool {
        if let matchedMenuItem = bestWindowMenuItem(for: terminal, matching: title),
           let scriptSource = terminal.appleScriptSelectWindowMenuItemCommand(title: matchedMenuItem),
           let output = executeAppleScript(scriptSource)?.stringValue,
           output == "matched" {
            return terminal != .ghostty || frontWindowMatchesAnyTitle(
                for: terminal,
                candidates: [matchedMenuItem, title]
            )
        }

        guard let scriptSource = terminal.appleScriptWindowFocusCommand(matching: title) else {
            return false
        }

        guard let output = executeAppleScript(scriptSource)?.stringValue else {
            return false
        }

        return output == "matched"
    }

    private func bestWindowMenuItem(for terminal: TerminalApplication, matching query: String) -> String? {
        guard let scriptSource = terminal.appleScriptWindowMenuItemsCommand,
              let descriptor = executeAppleScript(scriptSource) else {
            return nil
        }

        let candidates = stringValues(from: descriptor)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let bestIndex = WindowTitleMatcher.bestMatchIndex(for: query, in: candidates) else {
            return nil
        }

        return candidates[bestIndex]
    }

    private func stringValues(from descriptor: NSAppleEventDescriptor) -> [String] {
        guard descriptor.numberOfItems > 0 else {
            return descriptor.stringValue.map { [$0] } ?? []
        }

        return (1...descriptor.numberOfItems)
            .compactMap { descriptor.atIndex($0)?.stringValue }
    }

    private func frontWindowTitle(for terminal: TerminalApplication) -> String? {
        guard let scriptSource = terminal.appleScriptFrontWindowTitleCommand else {
            return nil
        }

        return executeAppleScript(scriptSource)?
            .stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func frontWindowMatchesAnyTitle(for terminal: TerminalApplication, candidates: [String]) -> Bool {
        let normalizedCandidates = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedCandidates.isEmpty else {
            return false
        }

        for attempt in 0..<5 {
            if let frontWindowTitle = frontWindowTitle(for: terminal),
               normalizedCandidates.contains(where: { candidate in
                   WindowTitleMatcher.score(candidate: frontWindowTitle, query: candidate) != nil
               }) {
                return true
            }

            if attempt < 4 {
                Thread.sleep(forTimeInterval: 0.15)
            }
        }

        return false
    }

    private func executeAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil {
            return nil
        }
        return result
    }
}
#endif
