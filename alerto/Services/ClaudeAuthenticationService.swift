import AppKit
import Foundation

enum ClaudeAuthenticationError: LocalizedError {
    case executableNotFound
    case terminalLaunchFailed

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Claude Code was not found. Run `claude auth login` in Terminal, then refresh Alerto."
        case .terminalLaunchFailed:
            return "Couldn't open Terminal for Claude Code authentication. Run `claude auth login` manually, then refresh Alerto."
        }
    }
}

/// Opens Claude Code's supported interactive login flow in Terminal.
@MainActor
final class ClaudeAuthenticationService {
    static let shared = ClaudeAuthenticationService()

    private init() {}

    func launchLogin() throws {
        let executablePath = try claudeExecutablePath()
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alerto-claude-auth-\(UUID().uuidString).command")
        let script = """
        #!/bin/zsh
        trap 'rm -f -- "$0"' EXIT
        echo "Starting Claude Code authentication..."
        \(shellQuote(executablePath)) auth login --claudeai
        status=$?
        if [ "$status" -eq 0 ]; then
            echo "Claude Code authentication completed. Return to Alerto and refresh usage."
        else
            echo "Claude Code authentication failed (exit code $status)."
        fi
        read -r "REPLY?Press Return to close this window..."
        exit "$status"
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            throw ClaudeAuthenticationError.terminalLaunchFailed
        }

        guard NSWorkspace.shared.open(scriptURL) else {
            try? FileManager.default.removeItem(at: scriptURL)
            throw ClaudeAuthenticationError.terminalLaunchFailed
        }
    }

    private func claudeExecutablePath() throws -> String {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/claude" })
        }

        if let match = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return match
        }
        throw ClaudeAuthenticationError.executableNotFound
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
