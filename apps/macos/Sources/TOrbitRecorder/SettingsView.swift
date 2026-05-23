import SwiftUI
import TOrbitRecorderCore

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Text("Output folder")
                .font(.headline)

            Text(appState.outputFolderPath)
                .textSelection(.enabled)

            Divider()

            Text("Auto-start")
                .font(.headline)

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { appState.autoStartSettings.isEnabled },
                    set: { appState.setAutoStartEnabled($0) }
                )
            )

            Stepper(
                value: Binding(
                    get: { appState.autoStartSettings.minDetectionDurationSeconds },
                    set: { appState.setAutoStartMinDetectionDurationSeconds($0) }
                ),
                in: 15...30,
                step: 5
            ) {
                Text("Detection duration: \(Int(appState.autoStartSettings.minDetectionDurationSeconds)) sec")
            }

            Stepper(
                value: Binding(
                    get: { appState.autoStartSettings.cooldownSeconds },
                    set: { appState.setAutoStartCooldownSeconds($0) }
                ),
                in: 60...600,
                step: 60
            ) {
                Text("Cooldown: \(Int(appState.autoStartSettings.cooldownSeconds / 60)) min")
            }

            TextField(
                "Whitelist",
                text: Binding(
                    get: { joined(appState.autoStartSettings.whitelist) },
                    set: { appState.setAutoStartWhitelist(split($0)) }
                )
            )
            .textFieldStyle(.roundedBorder)

            TextField(
                "Blacklist",
                text: Binding(
                    get: { joined(appState.autoStartSettings.blacklist) },
                    set: { appState.setAutoStartBlacklist(split($0)) }
                )
            )
            .textFieldStyle(.roundedBorder)

            Text("Last decision: \(appState.autoStartLastDecision)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(width: 560)
    }

    private func joined(_ values: [String]) -> String {
        values.joined(separator: ", ")
    }

    private func split(_ value: String) -> [String] {
        value.split(separator: ",").map { String($0) }
    }
}
