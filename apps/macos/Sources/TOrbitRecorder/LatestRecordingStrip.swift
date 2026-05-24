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

                if recording.audioProcessingStatus == .done {
                    Text("Balanced")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Audio balanced")
                }

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

                    Button {
                        onTag()
                    } label: {
                        Label("Tag", systemImage: "tag")
                    }
                    .accessibilityLabel("Tag latest recording")
                }
                .fixedSize()
            }

            if !recording.qualityWarnings.isEmpty {
                Label(recording.qualityWarnings.joined(separator: " "), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .accessibilityLabel(recording.qualityWarnings.joined(separator: " "))
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

    private func playMixed() {
        guard recording.mixedPreviewState == "Ready" else {
            return
        }

        NSWorkspace.shared.open(recording.mixedAudioURL)
    }
}
