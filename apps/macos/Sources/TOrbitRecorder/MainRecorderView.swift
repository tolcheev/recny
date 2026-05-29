import AppKit
import SwiftUI
import TOrbitRecorderCore

struct MainRecorderView: View {
    @ObservedObject var appState: AppState
    @State private var isCapturingScreenshot = false
    @State private var screenshotMessage: String?
    @State private var screenshotError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if appState.shouldShowPermissionChecklist {
                PermissionsOnboardingView(appState: appState)
            }
            RecordingStatusCard(appState: appState)
            screenshotFeedback
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
            return appState.isRecordingStartAllowed ? "Ready" : "Blocked"
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
                screenshotButton
                Spacer(minLength: 12)
                diagnosticsButton
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    recordsButton
                    libraryFolderButton
                    settingsButton
                    screenshotButton
                }
                diagnosticsButton
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var screenshotFeedback: some View {
        if let screenshotError {
            Label(screenshotError, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        } else if let screenshotMessage {
            Label(screenshotMessage, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
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

    private var screenshotButton: some View {
        Button {
            captureScreenshot()
        } label: {
            Label(isCapturingScreenshot ? "Capturing" : "Full Screenshot", systemImage: "camera.viewfinder")
        }
        .disabled(isCapturingScreenshot || appState.preferredScreenshotFolderURL == nil)
        .accessibilityLabel("Capture full-screen screenshot")
    }

    private var diagnosticsButton: some View {
        Button("Diagnostics") {
            AppWindows.openDiagnostics(appState: appState)
        }
        .buttonStyle(.link)
        .accessibilityLabel("Open Diagnostics")
    }

    private func captureScreenshot() {
        guard let sessionFolderURL = appState.preferredScreenshotFolderURL else {
            screenshotError = "Start a recording or keep a recent recording before taking a screenshot."
            screenshotMessage = nil
            return
        }

        isCapturingScreenshot = true
        screenshotError = nil
        screenshotMessage = nil

        Task {
            do {
                let screenshotURL = try await NativeScreenshotCapture.captureFullScreen(
                    sessionFolderURL: sessionFolderURL
                )
                await MainActor.run {
                    isCapturingScreenshot = false
                    screenshotMessage = "Screenshot saved: \(screenshotURL.lastPathComponent)"
                    screenshotError = nil
                }
            } catch NativeScreenshotError.cancelled {
                await MainActor.run {
                    isCapturingScreenshot = false
                }
            } catch {
                await MainActor.run {
                    isCapturingScreenshot = false
                    screenshotError = String(describing: error)
                    screenshotMessage = nil
                }
            }
        }
    }
}
