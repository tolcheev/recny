import AppKit
import Foundation
import SwiftUI
import TOrbitRecorderCore

struct DiagnosticsView: View {
    @ObservedObject var appState: AppState

    @State private var clearResult: String?
    @State private var testResult: String?
    @State private var isRunningTestRecording = false
    @State private var showRawError = false
    @State private var logLines: [String] = []
    @State private var logsResult: String?
    @State private var isClearLogsConfirmationPresented = false
    @State private var isReprocessingMissingAudio = false
    @State private var reprocessResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                permissionsSection
                deviceSection
                errorSection
                audioProcessingSection
                recoverableSection
                logsSection
                testRecordingSection
            }
            .padding(20)
        }
        .frame(minWidth: 700, minHeight: 560)
        .onAppear {
            appState.refreshMicrophoneDevices()
            appState.refreshPermissionSnapshot()
            try? appState.reloadRecoverableRecordings()
            loadRecentLogs()
        }
        .alert("Clear logs?", isPresented: $isClearLogsConfirmationPresented) {
            Button("Clear Logs", role: .destructive) {
                clearLogs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes app.log and app.1.log. Future app events will create a new app.log.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Diagnostics")
                .font(.title2.weight(.semibold))
            Text("Permissions, devices, recovery, logs, and test recording.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 10) {
                PermissionChecklistContent(appState: appState)

                HStack {
                    Spacer()

                    Button {
                        appState.refreshPermissionSnapshot()
                    } label: {
                        Label("Recheck", systemImage: "arrow.clockwise")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deviceSection: some View {
        GroupBox("Device Diagnostics") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DiagnosticLine(
                        label: "Selected input",
                        value: RecordingDisplayFormatter.microphoneName(appState.selectedMicrophoneName)
                    )

                    Spacer()

                    Button {
                        appState.refreshMicrophoneDevices()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                DiagnosticLine(
                    label: "Recommended input",
                    value: RecordingDisplayFormatter.microphoneName(appState.recommendedMicrophoneName)
                )

                DiagnosticLine(
                    label: "Reason",
                    value: appState.microphoneSelectionReason
                )

                if let warning = appState.microphoneInputWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Available input devices")
                        .font(.callout.weight(.medium))

                    if appState.availableMicrophoneDevices.isEmpty {
                        Text("No input devices detected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.availableMicrophoneDevices) { device in
                            HStack(spacing: 8) {
                                Text(device.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                DeviceRoleBadge(text: appState.microphoneDeviceLabel(for: device))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var errorSection: some View {
        GroupBox("Last Error") {
            VStack(alignment: .leading, spacing: 8) {
                if let errorMessage = appState.errorMessage {
                    Text(RecordingDisplayFormatter.humanReadableError(errorMessage))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.red)

                    Button(showRawError ? "Hide raw error" : "Show raw error") {
                        showRawError.toggle()
                    }
                    .buttonStyle(.link)

                    if showRawError {
                        Text(errorMessage)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("None")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recoverableSection: some View {
        GroupBox("Recoverable Recordings") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Interrupted sessions with usable audio files.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        do {
                            let removed = try appState.clearEmptyRecoverableRecordings()
                            clearResult = "Removed \(removed) empty recoverable folders."
                        } catch {
                            clearResult = String(describing: error)
                        }
                    } label: {
                        Label("Clear empty recoverables", systemImage: "trash")
                    }

                    Button {
                        try? appState.reloadRecoverableRecordings()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                if appState.recoverableRecordings.isEmpty {
                    Text("No recoverable recordings with usable files.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.recoverableRecordings) { recording in
                            RecoverableRecordingRow(recording: recording, appState: appState)
                        }
                    }
                }

                if let clearResult {
                    Text(clearResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var audioProcessingSection: some View {
        GroupBox("Audio Processing") {
            VStack(alignment: .leading, spacing: 8) {
                if let latest = appState.lastRecording {
                    DiagnosticLine(
                        label: "Balanced mix",
                        value: RecordingDisplayFormatter.audioProcessingCopy(state: latest.playbackDisplayState)
                    )
                    DiagnosticLine(
                        label: "Playback",
                        value: latest.mixedAudioURL.lastPathComponent
                    )
                    DiagnosticLine(
                        label: "Audio health",
                        value: RecordingDisplayFormatter.audioHealthBadgeText(latest.audioHealthStatus)
                    )
                    DiagnosticLine(
                        label: "Analysis",
                        value: latest.audioAnalysisURL.lastPathComponent
                    )

                    let healthDetails = RecordingDisplayFormatter.audioHealthDetails(
                        health: AudioHealthMetadata(
                            status: latest.audioHealthStatus,
                            warnings: latest.audioHealthWarnings
                        ),
                        processingStatus: latest.audioProcessingStatus
                    )
                    let details = healthDetails + latest.audioProcessingWarnings.filter { !healthDetails.contains($0) }
                    if !details.isEmpty {
                        Text(details.joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.open(latest.mixedAudioURL)
                        } label: {
                            Label("Play Current", systemImage: "play.fill")
                        }
                        .disabled(latest.mixedPreviewState != "Ready")

                        Button {
                            NSWorkspace.shared.open(latest.originalMixedAudioURL)
                        } label: {
                            Label("Play Original", systemImage: "waveform")
                        }
                        .disabled(!FileManager.default.fileExists(atPath: latest.originalMixedAudioURL.path(percentEncoded: false)))

                        Button {
                            NSWorkspace.shared.open(latest.audioAnalysisURL)
                        } label: {
                            Label("Open Analysis", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(RecordingPlaybackResolver.nonEmptyFileSize(at: latest.audioAnalysisURL) == nil)
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            runBatchAudioReprocess()
                        } label: {
                            Label("Reprocess Missing Balanced Audio", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isReprocessingMissingAudio || appState.audioReprocessProgress != nil)

                        if isReprocessingMissingAudio {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let progress = appState.audioReprocessProgress {
                        Text(progress.displayText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if let reprocessResult {
                        Text(reprocessResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("No latest recording yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button {
                        runBatchAudioReprocess()
                    } label: {
                        Label("Reprocess Missing Balanced Audio", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isReprocessingMissingAudio || appState.audioReprocessProgress != nil)

                    if let progress = appState.audioReprocessProgress {
                        Text(progress.displayText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if let reprocessResult {
                        Text(reprocessResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func runBatchAudioReprocess() {
        guard !isReprocessingMissingAudio else {
            return
        }

        isReprocessingMissingAudio = true
        reprocessResult = "Reprocessing missing balanced audio..."

        Task {
            do {
                let summary = try await appState.reprocessMissingBalancedAudio()
                reprocessResult = summary.results.isEmpty
                    ? "No recordings need balanced audio."
                    : summary.displayText
            } catch {
                reprocessResult = "Reprocess failed: \(String(describing: error))"
            }
            isReprocessingMissingAudio = false
        }
    }

    private var logsSection: some View {
        GroupBox("Logs") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(logFileURL.path(percentEncoded: false))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        loadRecentLogs()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button {
                        copyLogs()
                    } label: {
                        Label("Copy Logs", systemImage: "doc.on.doc")
                    }
                    .disabled(logLines.isEmpty)

                    Button {
                        openLogs()
                    } label: {
                        Label("Open Logs", systemImage: "folder")
                    }

                    Button(role: .destructive) {
                        isClearLogsConfirmationPresented = true
                    } label: {
                        Label("Clear Logs", systemImage: "trash")
                    }
                }

                if logLines.isEmpty {
                    Text("No local log lines yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(logLines.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(minHeight: 160, maxHeight: 220)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                }

                if let logsResult {
                    Text(logsResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var testRecordingSection: some View {
        GroupBox("Test Recording") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runs a 10 second local recording with the same pipeline as the main Start button.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    runTestRecording()
                } label: {
                    Label("Run 10 sec test recording", systemImage: "waveform")
                }
                .disabled(appState.status == .recording || isRunningTestRecording)

                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logsURL: URL {
        AppLogger.fileLogStore.logDirectoryURL
    }

    private var logFileURL: URL {
        AppLogger.fileLogStore.logFileURL
    }

    private func openLogs() {
        do {
            try FileManager.default.createDirectory(
                at: logsURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(logsURL)
        } catch {
            AppLogger.storage.error("Failed to open logs folder: \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "storage", "failed to open logs folder error=\(String(describing: error))")
        }
    }

    private func loadRecentLogs() {
        do {
            logLines = try AppLogger.fileLogStore.recentLines(limit: 100)
            logsResult = logLines.isEmpty ? "No app.log entries found." : "Loaded last \(logLines.count) log lines."
        } catch {
            logLines = []
            logsResult = String(describing: error)
        }
    }

    private func copyLogs() {
        let text = logLines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        logsResult = "Copied \(logLines.count) log lines."
    }

    private func clearLogs() {
        do {
            try AppLogger.fileLogStore.clear()
            logLines = []
            logsResult = "Logs cleared."
        } catch {
            logsResult = String(describing: error)
        }
    }

    private func runTestRecording() {
        isRunningTestRecording = true
        testResult = "Running 10 second test recording..."

        Task {
            do {
                try await appState.startRecording()
                try await Task.sleep(for: .seconds(10))
                try await appState.stopRecording()
                testResult = "Test recording stopped. Check Last Recording and Library."
            } catch {
                testResult = String(describing: error)
            }

            isRunningTestRecording = false
        }
    }
}

private struct DiagnosticLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(label):")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
            Spacer()
        }
    }
}

private struct RecoverableRecordingRow: View {
    let recording: RecoverableRecordingSummary
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(recording.id)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text("Recoverable")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Text("\(recording.segmentCount) segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(recording.recoverableFileCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(recording.startedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button("Recover Recording") {
                    Task {
                        try? await appState.recoverRecording(recording)
                    }
                }

                Button("Open Folder") {
                    NSWorkspace.shared.open(recording.folderURL)
                }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
