import AppKit
import UserNotifications

@MainActor
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private static let jumpActionID = "HERDR_JUMP"
    private static let categoryID = "HERDR_AGENT"
    nonisolated private static let paneIDKey = "pane_id"

    // Serial, so notification order is preserved and the blocking
    // `waitUntilExit` in launch is harmless. Keeps the process scan for the
    // jump command off the main thread as well.
    nonisolated private static let postQueue = DispatchQueue(label: "herdr-menubar.notify",
                                                             qos: .utility)

    private var isAuthorized = false

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([Self.agentCategory()])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.error("notification auth failed: \(error.localizedDescription)")
            }
            Log.debug("notification authorization granted=\(granted)")
            Task { @MainActor [weak self] in self?.isAuthorized = granted }
        }
    }

    // UNUserNotificationCenter refuses ad-hoc signed apps (the normal local build),
    // so fall back to the same tools Herdr itself uses. That path spawns
    // processes and scans the process table, so it runs off-main.
    func notify(title: String, body: String, paneID: String, sound: Bool) {
        if isAuthorized {
            postUserNotification(title: title, body: body, paneID: paneID, sound: sound)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Self.postQueue.async {
            if !Self.postViaTerminalNotifier(title: title, body: body, paneID: paneID,
                                             sound: sound, frontmost: frontmost) {
                Log.debug("falling back to AppleScript notification")
                Self.postViaAppleScript(title: title, body: body)
            }
        }
    }

    private static func agentCategory() -> UNNotificationCategory {
        let jump = UNNotificationAction(
            identifier: jumpActionID,
            title: "Jump to pane",
            options: [.foreground])
        return UNNotificationCategory(identifier: categoryID, actions: [jump],
                                      intentIdentifiers: [], options: [])
    }

    private func postUserNotification(title: String, body: String, paneID: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [Self.paneIDKey: paneID]
        if sound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: "herdr-\(paneID)-\(UUID().uuidString)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated private static func postViaTerminalNotifier(
        title: String, body: String, paneID: String, sound: Bool, frontmost: pid_t?
    ) -> Bool {
        guard let tool = Executables.locate("terminal-notifier") else { return false }

        var arguments = ["-title", title, "-message", body.isEmpty ? " " : body]
        if let command = jumpShellCommand(paneID: paneID, frontmost: frontmost) {
            arguments += ["-execute", command]
        }
        if sound { arguments += ["-sound", "default"] }

        do {
            try Self.launch(tool, arguments: arguments)
            Log.debug("posted via terminal-notifier")
            return true
        } catch {
            Log.debug("terminal-notifier failed: \(error.localizedDescription)")
            return false
        }
    }

    // Internal so the test target can check the quoting of the assembled command.
    // Every interpolated value is single-quoted: terminal-notifier runs `-execute`
    // through a shell, and the pane id comes from Herdr's JSON.
    nonisolated static func jumpShellCommand(paneID: String, frontmost: pid_t?) -> String? {
        guard let herdr = Executables.locate("herdr") else { return nil }
        var command = "\(ShellQuoting.quoted(herdr)) agent focus \(ShellQuoting.quoted(paneID))"
        if let bundleID = TerminalActivator.hostTerminalBundleID(frontmost: frontmost) {
            command += "; /usr/bin/open -b \(ShellQuoting.quoted(bundleID))"
        }
        return command
    }

    // Cannot carry a click action, but still gets the message across.
    nonisolated private static func postViaAppleScript(title: String, body: String) {
        try? Self.launch("/usr/bin/osascript", arguments: [
            "-e", "on run argv",
            "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
            "-e", "end run",
            title, body,
        ])
    }

    nonisolated private static func launch(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try process.run()
        // Blocking is fine on the post queue, and keeping the Process alive until
        // exit reaps the child instead of leaving a zombie per notification.
        process.waitUntilExit()
    }

    // Present even while the app is frontmost; it has no windows of its own.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let paneID = response.notification.request.content.userInfo[Self.paneIDKey] as? String
        Task { @MainActor in
            if let paneID { PaneNavigator.jump(to: paneID) }
            completionHandler()
        }
    }
}
