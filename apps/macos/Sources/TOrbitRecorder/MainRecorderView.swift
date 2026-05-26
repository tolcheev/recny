import AppKit
import SwiftUI
import TOrbitRecorderCore

struct MainRecorderView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if appState.shouldShowPermissionChecklist {
                PermissionsOnboardingView(appState: appState)
            }
            RecordingStatusCard(appState: appState)
            footerActions
        }
        .padding(18)
        .frame(
            minWidth: 520,
            idealWidth: 560,
            maxWidth: 620,
            minHeight: appState.shouldShowPermissionChecklist ? 540 : 360
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshMicrophoneDevices()
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
        HStack(alignment: .center, spacing: 10) {
            Spacer()

            StatusBadge(
                text: autoStartBadgeText,
                tone: appState.autoStartSettings.isEnabled ? .ready : .neutral
            )

            headerStatusIndicator
        }
    }

    private var autoStartBadgeText: String {
        switch appState.autoStartSettings.mode {
        case .off:
            return "Auto-start Off"
        case .askFirst:
            return "Auto-start Ask"
        case .auto:
            return "Auto-start On"
        }
    }

    private var headerStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(headerStatusTone.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(headerStatusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(headerStatusTone.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recorder status \(headerStatusText)")
    }

    private var headerStatusText: String {
        switch appState.status {
        case .recording:
            return "Recording"
        case .error:
            return "Error"
        case .idle:
            return appState.isRecordingStartAllowed ? "Ready" : "Error"
        }
    }

    private var headerStatusTone: StatusTone {
        switch appState.status {
        case .recording:
            return .recording
        case .error:
            return .danger
        case .idle:
            return appState.isRecordingStartAllowed ? .ready : .danger
        }
    }

    private var footerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                recordsButton
                libraryFolderButton
                settingsButton
                Spacer(minLength: 12)
                diagnosticsButton
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    recordsButton
                    libraryFolderButton
                    settingsButton
                }
                diagnosticsButton
            }
        }
        .padding(.top, 2)
    }

    private var recordsButton: some View {
        Button {
            AppWindows.openLibrary(appState: appState)
        } label: {
            Label("Records", systemImage: "tray.full")
        }
        .accessibilityLabel("Open records")
    }

    private var libraryFolderButton: some View {
        Button {
            AppWindows.openRecordingsFolder(appState: appState)
        } label: {
            Label("Library", systemImage: "folder")
        }
        .accessibilityLabel("Open local recording library folder")
    }

    private var settingsButton: some View {
        Button {
            AppWindows.openSettings(appState: appState)
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .accessibilityLabel("Open Settings")
    }

    private var diagnosticsButton: some View {
        Button("Diagnostics") {
            AppWindows.openDiagnostics(appState: appState)
        }
        .buttonStyle(.link)
        .accessibilityLabel("Open Diagnostics")
    }
}
