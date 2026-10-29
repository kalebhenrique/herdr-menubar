import ServiceManagement
import SwiftUI

@MainActor
final class Settings: ObservableObject {
    @AppStorage("notifyOnBlocked") var notifyOnBlocked = true
    @AppStorage("notifyOnDone") var notifyOnDone = false
    @AppStorage("playSound") var playSound = false
    @AppStorage("quitOnServerStop") var quitOnServerStop = false

    // Reads live SMAppService state so it stays correct when changed in System Settings.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            setLoginItemRegistered(newValue)
            objectWillChange.send()
        }
    }

    private func setLoginItemRegistered(_ registered: Bool) {
        do {
            if registered {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.error("login item change failed: \(error.localizedDescription)")
        }
    }

    @Published private(set) var isAliasInstalled: Bool = ShellIntegration.isInstalled()

    var shellConfigFilename: String {
        ShellIntegration.defaultShellConfigFile?.lastPathComponent ?? ".zshrc"
    }

    func refreshAliasStatus() {
        isAliasInstalled = ShellIntegration.isInstalled()
    }

    func installShellAlias() {
        do {
            try ShellIntegration.install()
            refreshAliasStatus()
        } catch {
            Log.error("failed to install shell alias: \(error.localizedDescription)")
        }
    }

    func uninstallShellAlias() {
        do {
            try ShellIntegration.uninstall()
            refreshAliasStatus()
        } catch {
            Log.error("failed to uninstall shell alias: \(error.localizedDescription)")
        }
    }

    func copyShellAlias() {
        ShellIntegration.copyToClipboard()
    }
}
