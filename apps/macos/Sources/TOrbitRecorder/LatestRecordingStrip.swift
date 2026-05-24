import AppKit
import SwiftUI
import TOrbitRecorderCore

struct LatestRecordingStrip: View {
    let recording: LastRecordingSummary
    let onTag: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(
                    RecordingDisplayFormatter.latestStripSummary(
                        status: recording.status,
                        duration: recording.durationSec,
                        micFileSizeBytes: recording.micFileSizeBytes,
                        systemFileSizeBytes: recording.systemFileSizeBytes
                    )
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel("Latest recording summary")

                playbackBadge

                audioHealthBadge

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Button {
                        playMixed()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(recording.mixedPreviewState != "Ready")
                    .accessibilityLabel("Play latest recording")

                    Button {
                        NSWorkspace.shared.open(recording.sessionFolderURL)
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                    .accessibilityLabel("Open latest recording folder")

                    Menu {
                        Button {
                            openIfExists(recording.balancedMixedAudioURL)
                        } label: {
                            Label("Play Balanced", systemImage: "slider.horizontal.3")
                        }
                        .disabled(!isNonEmptyFile(recording.balancedMixedAudioURL))

                        Button {
                            openIfExists(recording.originalMixedAudioURL)
                        } label: {
                            Label("Play Original", systemImage: "waveform")
                        }
                        .disabled(!isNonEmptyFile(recording.originalMixedAudioURL))

                        Divider()

                        Button {
                            NSWorkspace.shared.open(recording.sessionFolderURL)
                        } label: {
                            Label("Open Folder", systemImage: "folder")
                        }

                        Button {
                            openIfExists(recording.audioAnalysisURL)
                        } label: {
                            Label("Show Audio Analysis", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(!isNonEmptyFile(recording.audioAnalysisURL))

                        Divider()

                        Button {
                            onTag()
                        } label: {
                            Label("Tag", systemImage: "tag")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityLabel("More latest recording actions")

                    if recording.audioHealthStatus != .good {
                        Button {
                            openHealthDetails()
                        } label: {
                            Text("Details")
                        }
                        .buttonStyle(.link)
                        .accessibilityLabel("Open audio health details")
                    }
                }
                .fixedSize()
            }

            if !recording.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(recording.tags.prefix(3)), id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    if recording.tags.count > 3 {
                        Text("+\(recording.tags.count - 3)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Latest recording tags \(recording.tags.joined(separator: " "))")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        )
        .help(latestHelpText)
        .accessibilityElement(children: .contain)
    }

    private var latestHelpText: String {
        var parts = [recording.folderName]
        if let startConfidence = recording.startConfidence {
            parts.append("Confidence: \(startConfidence)")
        }
        if let startReason = recording.startReason {
            parts.append("Reason: \(startReason)")
        }
        return parts.joined(separator: "\n")
    }

    private var playbackBadge: some View {
        Text(RecordingDisplayFormatter.playbackStateText(recording.playbackDisplayState))
            .font(.caption.weight(.medium))
            .foregroundStyle(playbackBadgeColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(playbackBadgeColor.opacity(0.12), in: Capsule())
            .accessibilityLabel(RecordingDisplayFormatter.audioProcessingCopy(state: recording.playbackDisplayState))
    }

    private var playbackBadgeColor: Color {
        switch recording.playbackDisplayState {
        case .balancedReady:
            return .green
        case .balancedFailed:
            return .orange
        case .missing:
            return .red
        default:
            return .secondary
        }
    }

    private var audioHealthBadge: some View {
        Text(RecordingDisplayFormatter.audioHealthBadgeText(recording.audioHealthStatus))
            .font(.caption.weight(.medium))
            .foregroundStyle(audioHealthBadgeColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(audioHealthBadgeColor.opacity(0.12), in: Capsule())
            .accessibilityLabel(RecordingDisplayFormatter.audioHealthBadgeText(recording.audioHealthStatus))
    }

    private var audioHealthBadgeColor: Color {
        switch recording.audioHealthStatus {
        case .good:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        }
    }

    private func playMixed() {
        guard recording.mixedPreviewState == "Ready" else {
            return
        }

        NSWorkspace.shared.open(recording.mixedAudioURL)
    }

    private func openIfExists(_ url: URL) {
        guard isNonEmptyFile(url) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func openHealthDetails() {
        if isNonEmptyFile(recording.audioAnalysisURL) {
            NSWorkspace.shared.open(recording.audioAnalysisURL)
            return
        }

        NSWorkspace.shared.open(recording.sessionFolderURL)
    }

    private func isNonEmptyFile(_ url: URL) -> Bool {
        RecordingPlaybackResolver.nonEmptyFileSize(at: url) != nil
    }
}
