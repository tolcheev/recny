import AppKit
import SwiftUI
import TOrbitRecorderCore

struct LastRecordingCard: View {
    let recording: LastRecordingSummary?
    let onTag: () -> Void

    var body: some View {
        RecorderCard {
            HStack {
                Text("Last recording")
                    .font(.headline)

                Spacer()
            }

            if let recording {
                recordingContent(recording)
            } else {
                emptyContent
            }
        }
    }

    private func recordingContent(_ recording: LastRecordingSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StatusBadge(
                    text: RecordingDisplayFormatter.statusText(recording.status),
                    tone: tone(for: recording.status)
                )

                if let subtitle = RecordingDisplayFormatter.statusSubtitle(recording.status) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(recording.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(
                    label: "Duration",
                    value: RecordingDisplayFormatter.duration(recording.durationSec)
                )
                InfoRow(
                    label: "Audio",
                    value: RecordingDisplayFormatter.audioSummary(
                        micFileSizeBytes: recording.micFileSizeBytes,
                        systemFileSizeBytes: recording.systemFileSizeBytes
                    )
                )
                InfoRow(label: "Folder", value: recording.folderName)
                InfoRow(label: "Files", value: fileSizes(recording))
            }

            HStack(spacing: 10) {
                Button {
                    playMixed(recording)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(recording.mixedPreviewState != "Ready")
                .accessibilityLabel("Play last recording")

                Button {
                    NSWorkspace.shared.open(recording.sessionFolderURL)
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .accessibilityLabel("Open last recording folder")

                Button {
                    onTag()
                } label: {
                    Label("Tag", systemImage: "tag")
                }
                .accessibilityLabel("Tag last recording")
            }
        }
    }

    private var emptyContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("No recordings yet")
                    .font(.callout.weight(.medium))
                Text("Start a recording or wait for auto-start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fileSizes(_ recording: LastRecordingSummary) -> String {
        [
            "Mic \(RecordingDisplayFormatter.fileSize(recording.micFileSizeBytes))",
            "System \(RecordingDisplayFormatter.fileSize(recording.systemFileSizeBytes))",
            "Mixed \(RecordingDisplayFormatter.fileSize(recording.mixedFileSizeBytes))"
        ].joined(separator: " · ")
    }

    private func playMixed(_ recording: LastRecordingSummary) {
        guard recording.mixedPreviewState == "Ready" else {
            return
        }

        NSWorkspace.shared.open(recording.mixedAudioURL)
    }
}
