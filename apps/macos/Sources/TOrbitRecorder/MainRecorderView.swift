import AppKit
import SwiftUI
import TOrbitRecorderCore

struct MainRecorderView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if appState.shouldShowPermissionsOnboarding {
                PermissionsOnboardingView(appState: appState)
            }
            RecordingStatusCard(appState: appState)
            if let lastRecording = appState.lastRecording {
                LatestRecordingStrip(recording: lastRecording) {
                    appState.editLastRecordingTags()
                }
            }
            footerActions
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 620, maxWidth: 720, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshPermissionSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionSnapshot()
        }
        .sheet(isPresented: $appState.isPostCallPanelPresented) {
            if let draft = appState.postCallDraft {
                TagEditorView(draft: draft) { updatedDraft in
                    try appState.savePostCallDraft(updatedDraft)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "record.circle.fill")
                .font(.title2)
                .foregroundStyle(appState.status == .recording ? .red : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("TOrbit Recorder")
                    .font(.title2.weight(.semibold))
                Text("Local audio recorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(
                text: appState.autoStartSettings.isEnabled ? "Auto-start On" : "Auto-start Off",
                tone: appState.autoStartSettings.isEnabled ? .ready : .neutral
            )
        }
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Button {
                AppWindows.openLibrary(appState: appState)
            } label: {
                Label("Library", systemImage: "tray.full")
            }
            .accessibilityLabel("Open Library")

            Button {
                AppWindows.openSettings(appState: appState)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityLabel("Open Settings")

            Spacer()

            Button("Diagnostics") {
                AppWindows.openDiagnostics(appState: appState)
            }
            .buttonStyle(.link)
            .accessibilityLabel("Open Diagnostics")
        }
        .padding(.top, 2)
    }
}
