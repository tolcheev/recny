import AppKit
import SwiftUI
import RecnyCore

struct MainRecorderView: View {
    @ObservedObject var appState: AppState
    @State private var isCapturingScreenshot = false
    @State private var screenshotMessage: String?
    @State private var screenshotError: String?
    @State private var updateReminderState = AppUpdateReminderStore.load()
    @State private var availableUpdateRelease: AppUpdateRelease?
    @State private var updateMessage: String?
    @State private var updateError: String?
    @State private var isCheckingForUpdates = false

    var body: some View {
        let policy = layoutPolicy

        VStack(alignment: .leading, spacing: 12) {
            if policy.usesScrollableMainContent {
                ScrollView(.vertical) {
                    mainContent(policy: policy)
                        .padding(.vertical, 2)
                }
                .frame(minHeight: CGFloat(policy.minimumScrollableContentHeight))
            } else {
                mainContent(policy: policy)
            }

            footerActions
            updateFooter
        }
        .padding(18)
        .frame(
            minWidth: CGFloat(policy.minimumWindowWidth),
            idealWidth: CGFloat(policy.idealWindowWidth),
            maxWidth: CGFloat(policy.maximumWindowWidth),
            minHeight: CGFloat(policy.minimumWindowHeight)
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshMicrophoneDevices()
            appState.refreshPermissionSnapshot()
            runAutomaticUpdateCheckIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppUpdateEvents.updateAvailable)) { notification in
            guard let release = AppUpdateEvents.release(from: notification),
                  appState.status != .recording
            else {
                return
            }

            availableUpdateRelease = release
            updateMessage = nil
            updateError = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AppUpdateEvents.updateDismissed)) { notification in
            guard let version = AppUpdateEvents.dismissedVersion(from: notification),
                  availableUpdateRelease?.version == version
            else {
                return
            }

            availableUpdateRelease = nil
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

    private var layoutPolicy: MainRecorderLayoutPolicy {
        MainRecorderLayoutPolicy(
            showsPermissionChecklist: appState.shouldShowPermissionChecklist,
            hasUpdateBanner: availableUpdateRelease != nil && appState.status != .recording,
            status: appState.status
        )
    }

    private func mainContent(policy: MainRecorderLayoutPolicy) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(policy.mainContentSpacing)) {
            header
            if appState.shouldShowPermissionChecklist {
                PermissionsOnboardingView(appState: appState)
            }
            if policy.showsRecordingStatusCard {
                RecordingStatusCard(appState: appState)
            }
            screenshotFeedback
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            return appState.isStoppingRecording ? "Saving" : "Recording"
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

    private var updateFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            if let availableUpdateRelease,
               appState.status != .recording {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        updateAvailableLabel(availableUpdateRelease)
                        Spacer(minLength: 8)
                        updateActionButtons(availableUpdateRelease)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        updateAvailableLabel(availableUpdateRelease)
                        updateActionButtons(availableUpdateRelease)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Text("Recny \(BuildInfo.appVersion)")
                            .foregroundStyle(.secondary)
                        if let updateMessage {
                            Text("· \(updateMessage)")
                                .foregroundStyle(.secondary)
                        }
                        if let updateError {
                            Text("· \(updateError)")
                                .foregroundStyle(.red)
                        }
                        Spacer(minLength: 8)
                        bugReportButton
                        checkUpdatesButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Recny \(BuildInfo.appVersion)")
                                .foregroundStyle(.secondary)
                            if let updateMessage {
                                Text("· \(updateMessage)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let updateError {
                            Text(updateError)
                                .foregroundStyle(.red)
                        }
                        HStack(spacing: 8) {
                            bugReportButton
                            checkUpdatesButton
                        }
                    }
                }
                .font(.caption)
            }
        }
    }

    private func updateAvailableLabel(_ release: AppUpdateRelease) -> some View {
        Label("Update available: \(release.displayVersion)", systemImage: "arrow.down.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.blue)
            .textSelection(.enabled)
    }

    private func updateActionButtons(_ release: AppUpdateRelease) -> some View {
        HStack(spacing: 8) {
            Button("Download") {
                NSWorkspace.shared.open(release.downloadURL)
            }

            Button("Later") {
                AppUpdateReminderPolicy.remindLater(
                    state: &updateReminderState,
                    release: release,
                    now: Date()
                )
                AppUpdateReminderStore.save(updateReminderState)
                AppUpdateEvents.postDismissed(version: release.version)
                availableUpdateRelease = nil
                updateMessage = "Will remind later."
                updateError = nil
            }

            Button("Skip") {
                AppUpdateReminderPolicy.skip(state: &updateReminderState, release: release)
                AppUpdateReminderStore.save(updateReminderState)
                AppUpdateEvents.postDismissed(version: release.version)
                availableUpdateRelease = nil
                updateMessage = "Skipped \(release.displayVersion)."
                updateError = nil
            }
        }
        .font(.caption)
    }

    private var checkUpdatesButton: some View {
        Button(isCheckingForUpdates ? "Checking..." : "Check for Updates") {
            runManualUpdateCheck()
        }
        .buttonStyle(.link)
        .disabled(isCheckingForUpdates || appState.status == .recording)
    }

    private var bugReportButton: some View {
        Button("Report Bug") {
            openBugReport()
        }
        .buttonStyle(.link)
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

    private func runAutomaticUpdateCheckIfNeeded() {
        let now = Date()
        guard AppUpdateReminderPolicy.shouldRunAutomaticCheck(
            now: now,
            state: updateReminderState,
            isRecording: appState.status == .recording
        ) else {
            return
        }

        AppUpdateReminderPolicy.markAutomaticCheck(state: &updateReminderState, now: now)
        AppUpdateReminderStore.save(updateReminderState)
        runUpdateCheck(isAutomatic: true)
    }

    private func runManualUpdateCheck() {
        runUpdateCheck(isAutomatic: false)
    }

    private func runUpdateCheck(isAutomatic: Bool) {
        guard !isCheckingForUpdates,
              appState.status != .recording
        else {
            return
        }

        isCheckingForUpdates = true
        if !isAutomatic {
            updateMessage = "Checking latest release..."
            updateError = nil
        }

        Task {
            do {
                let result = try await AppUpdateChecker().check(
                    platform: .macOS,
                    currentVersion: BuildInfo.appVersion
                )
                let shouldSurface = AppUpdateReminderPolicy.shouldSurfaceUpdate(
                    result: result,
                    state: updateReminderState,
                    now: Date(),
                    isRecording: appState.status == .recording
                )

                await MainActor.run {
                    isCheckingForUpdates = false
                    updateError = nil
                    if shouldSurface {
                        availableUpdateRelease = result.latestRelease
                        AppUpdateEvents.postAvailable(result.latestRelease)
                        updateMessage = nil
                    } else if !isAutomatic {
                        availableUpdateRelease = nil
                        updateMessage = result.displayText
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingForUpdates = false
                    if !isAutomatic {
                        availableUpdateRelease = nil
                        updateMessage = nil
                        updateError = "Could not check updates: \(String(describing: error))"
                    }
                    AppLogger.file(.error, category: "app", "main update check failed automatic=\(isAutomatic) error=\(String(describing: error))")
                }
            }
        }
    }

    private func openBugReport() {
        guard let url = AppSupportLinks.bugReportURL(
            version: BuildInfo.appVersion,
            platform: .macOS
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
