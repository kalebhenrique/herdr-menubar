/// Single-quote quoting for POSIX shell words. Inside single quotes everything
/// is literal, so arbitrary values (pane ids, paths, bundle ids) can travel
/// through shell commands — including the ones terminal-notifier runs when a
/// notification is clicked — without `;`, spaces or `$(...)` breaking out.
enum ShellQuoting {
    /// The only special character inside single quotes is the quote itself,
    /// which is closed, escaped, and reopened: `'` becomes `'\''`.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
