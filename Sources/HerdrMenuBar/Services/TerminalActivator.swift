import AppKit

// Herdr can only move focus inside itself; raising the terminal window is a macOS job.
// Walking the client's parent chain finds the exact hosting instance, unlike TERM_PROGRAM.
//
// The scan is pure sysctl + `NSRunningApplication` lookups (both thread-safe), so it
// can run off the main thread; the one main-thread input, the frontmost app, is
// captured by the caller and passed in as `frontmost`.
enum TerminalActivator {
    private static let herdrProcessName = "herdr"
    private static let serverArgument = "server"
    private static let maxAncestorHops = 16

    /// Raises the terminal hosting the herdr client. `frontmost` must be captured
    /// on the main thread by the caller; the activation itself hops back to main,
    /// the only AppKit call that must run there.
    static func activateHostTerminal(frontmost: pid_t?) {
        guard let pid = hostTerminalProcessID(frontmost: frontmost) else { return }
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        }
    }

    static func hostTerminalBundleID(frontmost: pid_t?) -> String? {
        guard let pid = hostTerminalProcessID(frontmost: frontmost) else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private static func hostTerminalProcessID(frontmost: pid_t?) -> pid_t? {
        guard let clientPID = herdrClientPIDs(frontmost: frontmost).first else { return nil }
        return guiAncestor(of: clientPID)?.processIdentifier
    }

    private static func herdrClientPIDs(frontmost: pid_t?) -> [pid_t] {
        let clients = ProcessInspector.allPIDs().filter(isHerdrClient)
        return clients.sorted { lhs, rhs in
            let lhsInFront = guiAncestor(of: lhs)?.processIdentifier == frontmost
            let rhsInFront = guiAncestor(of: rhs)?.processIdentifier == frontmost
            if lhsInFront != rhsInFront { return lhsInFront }
            return lhs < rhs
        }
    }

    private static func isHerdrClient(_ pid: pid_t) -> Bool {
        ProcessInspector.name(of: pid) == herdrProcessName
            && !ProcessInspector.arguments(of: pid).contains(serverArgument)
    }

    // Shells, `login` and the Herdr client have no bundle identifier, so the first
    // ancestor with one is the terminal emulator.
    private static func guiAncestor(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<maxAncestorHops {
            if let app = NSRunningApplication(processIdentifier: current),
               app.bundleIdentifier != nil {
                return app
            }
            guard let parent = ProcessInspector.parentPID(of: current),
                  parent > 1, parent != current
            else { return nil }
            current = parent
        }
        return nil
    }
}
