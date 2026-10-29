import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject private var settings: Settings
    var onClose: (() -> Void)? = nil
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onClose {
                    Button("Done", action: onClose)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .pointerCursor()
                }
            }
            .padding(.bottom, 2)

            Toggle("Notify when an agent needs me", isOn: $settings.notifyOnBlocked)
            Toggle("Notify when an agent finishes", isOn: $settings.notifyOnDone)
            Toggle("Play a sound", isOn: $settings.playSound)
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.launchAtLogin = $0 }))
            Toggle("Quit when Herdr stops", isOn: $settings.quitOnServerStop)

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Terminal Integration")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if settings.isAliasInstalled {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 11))
                        Text("Active in ~/\(settings.shellConfigFilename)")
                            .font(.system(size: 11))
                        Spacer(minLength: 4)
                        Button("Remove") {
                            settings.uninstallShellAlias()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .pointerCursor()
                    }
                } else {
                    Button {
                        settings.installShellAlias()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "terminal")
                                .font(.system(size: 10))
                            Text("Add to ~/\(settings.shellConfigFilename)")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointerCursor()
                }

                Button {
                    settings.copyShellAlias()
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy shell wrapper")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(12)
        .onAppear {
            settings.refreshAliasStatus()
        }
    }
}
