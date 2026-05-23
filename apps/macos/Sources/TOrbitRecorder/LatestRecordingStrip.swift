import AppKit
import SwiftUI
import TOrbitRecorderCore

struct LatestRecordingStrip: View {
    let recording: LastRecordingSummary
    let onTag: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Latest")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    StatusBadge(
                        text: RecordingDisplayFormatter.statusText(recording.status),
                        tone: tone(for: recording.status)
                    )
                }

                Text(recording.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Text(
                    RecordingDisplayFormatter.latestRecordingDetail(
                        status: recording.status,
                        duration: recording.durationSec,
                        micFileSizeBytes: recording.micFileSizeBytes,
                        systemFileSizeBytes: recording.systemFileSizeBytes
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
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
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func playMixed() {
        guard recording.mixedPreviewState == "Ready" else {
            return
        }

        NSWorkspace.shared.open(recording.mixedAudioURL)
    }
}
