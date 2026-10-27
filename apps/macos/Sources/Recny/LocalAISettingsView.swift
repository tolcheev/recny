import AppKit
import SwiftUI
import RecnyCore

struct LocalAISettingsView: View {
    @ObservedObject private var coordinator = LocalProcessingCoordinator.shared
    @State private var status = LocalAIStatus(ready: false, message: "Checking local notes setup…")
    @State private var runtimeInstalled = false
    @State private var preparationTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var isChecking = false
    private let setup = LocalAISetup()

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Optional local notes use MLX LM and a prepared Qwen3 4B model. Audio and text stay on this Mac. Model preparation downloads model files; processing uses local files only.")
                    .font(.caption).foregroundStyle(.secondary)
                Label(runtimeInstalled ? "Local runtime installed" : "Local runtime missing", systemImage: runtimeInstalled ? "checkmark.circle" : "exclamationmark.circle")
                Text(status.message).font(.callout).textSelection(.enabled)
                HStack {
                    Button("Check Setup") { Task { await refreshStatus() } }
                        .disabled(isChecking || preparationTask != nil)
                    Button("Copy Runtime Install Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(setup.installCommand, forType: .string)
                    }
                    if preparationTask == nil {
                        Button(status.ready ? "Verify / Repair Model" : "Download & Prepare Model") { prepareModel() }
                            .disabled(!runtimeInstalled || coordinator.isBusy || isChecking)
                    } else {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { preparationTask?.cancel() }
                    }
                }
                Text(setup.installCommand).font(.caption.monospaced()).textSelection(.enabled)
                Text("Requires uv and Python 3.11. The isolated runtime is separate from Parakeet. Preparation may take several minutes and needs several GB of free disk space.")
                    .font(.caption).foregroundStyle(.secondary)
                if coordinator.isBusy {
                    Text("Wait for local recording processing to finish before preparing the notes model.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
        } label: {
            Text("Local Notes").font(.headline)
        }
        .task { await refreshStatus() }
        .onDisappear { preparationTask?.cancel() }
    }

    private func refreshStatus() async {
        guard !isChecking else { return }
        isChecking = true
        runtimeInstalled = setup.runtimeInstalled
        status = await setup.notesStatus()
        isChecking = false
    }

    private func prepareModel() {
        guard preparationTask == nil, !coordinator.isBusy else { return }
        errorMessage = nil
        status = .init(ready: false, message: "Downloading and preparing local notes model…")
        preparationTask = Task {
            do {
                try await setup.prepareNotesModel()
                try Task.checkCancellation()
            } catch is CancellationError {
                errorMessage = "Model preparation cancelled. Prepare again to complete the local setup."
            } catch {
                errorMessage = error.localizedDescription
            }
            await refreshStatus()
            preparationTask = nil
        }
    }
}
