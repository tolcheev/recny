import SwiftUI
import RecnyCore

struct AudioTrimSheet: View {
    let recording: RecordingSummary
    let displayTitle: String
    let onExported: (AudioTrimResult, Bool) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sourceAudio: RecordingPlaybackCandidate?
    @State private var durationSeconds: Double = 0
    @State private var startSeconds: Double = 0
    @State private var endSeconds: Double = 0
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trim Audio")
                    .font(.headline)
                Text(displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if isLoading {
                ProgressView("Reading audio...")
            } else if let sourceAudio {
                VStack(alignment: .leading, spacing: 12) {
                    detailRow("Source", "\(sourceAudio.kind.displayName) · \(sourceAudio.url.lastPathComponent)")
                    detailRow("Duration", formatTime(durationSeconds))
                    detailRow("Clip", "\(formatTime(startSeconds)) - \(formatTime(endSeconds)) (\(formatTime(clipDuration)))")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Start")
                            .font(.caption.weight(.medium))
                        Slider(value: $startSeconds, in: startRange)
                            .disabled(isExporting)
                            .onChange(of: startSeconds) { _, value in
                                if endSeconds - value < 0.05 {
                                    endSeconds = min(durationSeconds, value + 0.05)
                                }
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("End")
                            .font(.caption.weight(.medium))
                        Slider(value: $endSeconds, in: endRange)
                            .disabled(isExporting)
                            .onChange(of: endSeconds) { _, value in
                                if value - startSeconds < 0.05 {
                                    startSeconds = max(0, value - 0.05)
                                }
                            }
                    }
                }
            } else {
                Label("No local audio file is available for trimming.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel", role: .cancel) {
                    onCancel()
                    dismiss()
                }
                .disabled(isExporting)

                Button {
                    exportClip(shareAfterExport: false)
                } label: {
                    Label("Trim Only", systemImage: "scissors")
                }
                .disabled(!canExport)

                Button {
                    exportClip(shareAfterExport: true)
                } label: {
                    Label(isExporting ? "Trimming..." : "Trim & Share", systemImage: "square.and.arrow.up")
                }
                .disabled(!canExport)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await loadAudio()
        }
    }

    private var clipDuration: Double {
        max(0, endSeconds - startSeconds)
    }

    private var startRange: ClosedRange<Double> {
        0...max(0, min(durationSeconds, endSeconds - 0.05))
    }

    private var endRange: ClosedRange<Double> {
        let lowerBound = min(durationSeconds, max(0.05, startSeconds + 0.05))
        return lowerBound...max(lowerBound, durationSeconds)
    }

    private var canExport: Bool {
        sourceAudio != nil && !isLoading && !isExporting && clipDuration >= 0.05
    }

    private func loadAudio() async {
        guard let candidate = RecordingPlaybackResolver.preferredShareableAudio(
            sessionFolderURL: recording.sessionFolderURL
        ) else {
            await MainActor.run {
                sourceAudio = nil
                isLoading = false
            }
            return
        }

        do {
            let duration = try await AudioTrimExporter.audioDuration(of: candidate.url)
            await MainActor.run {
                sourceAudio = candidate
                durationSeconds = duration
                startSeconds = 0
                endSeconds = duration
                errorMessage = nil
                isLoading = false
            }
        } catch {
            await MainActor.run {
                sourceAudio = nil
                errorMessage = String(describing: error)
                isLoading = false
            }
        }
    }

    private func exportClip(shareAfterExport: Bool) {
        guard let sourceAudio else {
            return
        }

        isExporting = true
        errorMessage = nil

        Task {
            do {
                let outputURL = RecordingDerivedArtifactPaths.trimmedAudioURL(
                    sessionFolderURL: recording.sessionFolderURL
                )
                let result = try await AudioTrimExporter().exportClip(
                    sourceURL: sourceAudio.url,
                    outputURL: outputURL,
                    startSeconds: startSeconds,
                    endSeconds: endSeconds
                )
                await MainActor.run {
                    isExporting = false
                    onExported(result, shareAfterExport)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = String(describing: error)
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, seconds)
        let minutes = Int(totalSeconds) / 60
        let wholeSeconds = Int(totalSeconds) % 60
        let tenths = Int((totalSeconds - Double(Int(totalSeconds))) * 10)
        return String(format: "%02d:%02d.%d", minutes, wholeSeconds, tenths)
    }
}
