import Foundation
import Darwin

enum ControllingTTY {
    static func current() -> String? {
        if let tty = ttyPath(for: STDIN_FILENO) {
            return tty
        }
        if let tty = ttyPath(for: STDOUT_FILENO) {
            return tty
        }
        if let tty = ttyPath(for: STDERR_FILENO) {
            return tty
        }

        let descriptor = open("/dev/tty", O_RDONLY)
        guard descriptor >= 0 else {
            return nil
        }
        defer { close(descriptor) }

        return ttyPath(for: descriptor)
    }

    private static func ttyPath(for fileDescriptor: Int32) -> String? {
        guard let pointer = ttyname(fileDescriptor) else {
            return nil
        }
        return String(cString: pointer).trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
