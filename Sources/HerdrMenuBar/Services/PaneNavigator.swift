import AppKit

enum PaneNavigator {
    /// Serial so rapid clicks queue instead of racing duplicate process scans,
    /// and so the blocking socket request below can never overlap itself.
    private static let jumpQueue = DispatchQueue(label: "herdr-menubar.pane-jump",
                                                 qos: .userInitiated)

    /// Fire-and-forget; call from the main thread. The socket request waits up
    /// to 5 seconds for a reply and the terminal scan walks the whole process
    /// table, so both run on the queue — a slow or hung Herdr server must not
    /// freeze the dropdown.
    static func jump(to paneID: String) {
        // Main-thread input for the scan; captured before leaving the main thread.
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        jumpQueue.async {
            do {
                try HerdrClient().focus(paneID: paneID)
            } catch {
                Log.error("pane.focus failed: \(error.localizedDescription)")
            }
            // Activation happens even when focus failed, as before: the user
            // asked for the terminal, not for silence.
            TerminalActivator.activateHostTerminal(frontmost: frontmost)
        }
    }
}
