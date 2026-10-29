import AppKit
import Foundation

enum ShellIntegration {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.aditya24sharma.herdr-menubar"
    static let startCommentMarker = "# Herdr Menu Bar integration"
    static let legacyCommentMarker = "# Herdr Menu Bar auto-start"
    static let endCommentMarker = "# End Herdr Menu Bar integration"

    static var shellSnippet: String {
        """
        \(startCommentMarker)
        herdr() {
            if [[ "$1" == "server" && "$2" == "stop" ]]; then
                command herdr "$@"
                osascript -e 'quit app id "\(bundleIdentifier)"' 2>/dev/null || true
            else
                open -b \(bundleIdentifier) --background 2>/dev/null || true
                command herdr "$@"
            fi
        }
        \(endCommentMarker)
        """
    }

    static var defaultShellConfigFile: URL? {
        if let customConfig = ProcessInfo.processInfo.environment["HERDR_CONFIG_FILE"], !customConfig.isEmpty {
            return URL(fileURLWithPath: customConfig)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let zshrc = home.appendingPathComponent(".zshrc")
        let bashrc = home.appendingPathComponent(".bashrc")
        let bashProfile = home.appendingPathComponent(".bash_profile")

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        if shell.contains("zsh") {
            return zshrc
        } else if shell.contains("bash") {
            if FileManager.default.fileExists(atPath: bashrc.path) {
                return bashrc
            }
            return bashProfile
        }

        if FileManager.default.fileExists(atPath: zshrc.path) {
            return zshrc
        } else if FileManager.default.fileExists(atPath: bashrc.path) {
            return bashrc
        }
        return zshrc
    }

    static func isInstalled(in fileURL: URL? = defaultShellConfigFile) -> Bool {
        guard let url = fileURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return content.contains(bundleIdentifier) && (content.contains("herdr()") || content.contains("alias herdr="))
    }

    @discardableResult
    static func install(in fileURL: URL? = defaultShellConfigFile) throws -> URL {
        guard let url = fileURL else {
            throw NSError(
                domain: "ShellIntegration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not determine shell configuration file."]
            )
        }

        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        if content.contains(startCommentMarker) && content.contains(endCommentMarker) {
            return url
        }

        // Clean any existing legacy alias or integration first
        if isInstalled(in: url) {
            _ = try? uninstall(in: url)
            content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        var block = "\n\(shellSnippet)\n"
        if !content.isEmpty && !content.hasSuffix("\n") {
            block = "\n" + block
        }

        content.append(block)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    static func uninstall(in fileURL: URL? = defaultShellConfigFile) throws -> URL {
        guard let url = fileURL else {
            throw NSError(
                domain: "ShellIntegration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not determine shell configuration file."]
            )
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return url
        }

        let lines = content.components(separatedBy: .newlines)
        var filteredLines: [String] = []
        var insideBlock = false
        var skipNextLegacy = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == startCommentMarker {
                insideBlock = true
                continue
            }
            if insideBlock {
                if trimmed == endCommentMarker {
                    insideBlock = false
                }
                continue
            }

            if trimmed == legacyCommentMarker {
                skipNextLegacy = true
                continue
            }
            if skipNextLegacy {
                if trimmed.starts(with: "alias herdr=") {
                    skipNextLegacy = false
                    continue
                }
                skipNextLegacy = false
            }

            if trimmed.contains("alias herdr=") && trimmed.contains(bundleIdentifier) {
                continue
            }

            filteredLines.append(line)
        }

        let newContent = filteredLines.joined(separator: "\n")
        try newContent.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shellSnippet, forType: .string)
    }

    @discardableResult
    static func handleCommandLine(_ arguments: [String]) -> Bool {
        guard arguments.count > 1 else { return false }

        let arg = arguments[1]
        switch arg {
        case "--install-alias", "--install", "install-alias", "setup":
            do {
                let targetURL = try install()
                print("Successfully installed Herdr terminal integration in \(targetURL.path)")
                print("\nAdded integration:")
                print(shellSnippet)
                print("\nTo activate it in your current terminal session, run:")
                print("  source \(targetURL.path)")
                return true
            } catch {
                fputs("Error installing integration: \(error.localizedDescription)\n", stderr)
                exit(1)
            }

        case "--uninstall-alias", "--uninstall", "uninstall-alias":
            do {
                let targetURL = try uninstall()
                print("Successfully removed Herdr integration from \(targetURL.path)")
                return true
            } catch {
                fputs("Error removing integration: \(error.localizedDescription)\n", stderr)
                exit(1)
            }

        case "--print-alias", "--print-snippet", "print-alias":
            print(shellSnippet)
            return true

        case "--status-alias", "--status", "status-alias":
            if let file = defaultShellConfigFile {
                let installed = isInstalled(in: file)
                print("Shell config: \(file.path)")
                print("Status: \(installed ? "Installed" : "Not installed")")
            } else {
                print("Could not locate shell config file.")
            }
            return true

        case "--help", "-h", "help":
            print("""
            Herdr Menu Bar - Companion CLI Options

            Usage:
              HerdrMenuBar [option]

            Options:
              --install           Install shell wrapper into configuration (~/.zshrc)
                                  Starts the menu bar on `herdr` and stops it on `herdr server stop`.
              --uninstall         Remove the integration from your shell configuration
              --print-snippet     Print the shell wrapper function
              --status            Check if the integration is currently installed
              --help, -h          Show this help message

            When run without options, launches the Menu Bar application.
            """)
            return true

        default:
            return false
        }
    }
}
